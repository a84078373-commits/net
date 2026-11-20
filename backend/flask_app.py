"""Flask app: HTML site + JSON API for the SmartCare mobile client."""
from __future__ import annotations

import hashlib
import hmac
import ipaddress
import math
import os
import re
import secrets
import socket
import sqlite3
import statistics
import threading
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from urllib.parse import urlencode, urlsplit

# Stay signed in until explicit logout (browser cookie max ~400 days).
SESSION_TTL_SECONDS = int(os.getenv('SMARTCARE_SESSION_TTL_SECONDS', str(365 * 24 * 60 * 60)))

import httpx
from flask import (
    Flask,
    Response,
    g,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)
from flask_cors import CORS
from werkzeug.exceptions import HTTPException

from backend.core import (
    MIB,
    QUALITY,
    Database,
    Settings,
    cell_bounds,
    cell_for,
    cell_id,
    classify,
    default_gemini_api_key,
    load_settings,
)
from backend.demo_seed import print_demo_credentials, seed_demo_hail
from backend.countries import countries_public, get_country, validate_and_store_phone
from backend.green_api import (
    delete_notification,
    green_config_from_env_and_db,
    incoming_text,
    otp_message_ar,
    receive_notification,
    send_whatsapp_text,
)
from backend.twin import (
    build_planning_towers,
    cells_from_measurements,
    compare_tower_sets,
    enrich_cells,
    ensure_grid_cells,
    sector_label,
    simulate_scenario,
)
from backend.i18n import (
    DEFAULT_LANG,
    GEMINI_INSTRUCTIONS,
    LANG_COOKIE,
    LANG_LABELS,
    RTL_LANGS,
    js_strings,
    normalize_lang,
    translate,
)

PHONE_RE = re.compile(r'^05\d{8}$')  # legacy Saudi login
PHONE_STORAGE_RE = re.compile(r'^(05\d{8}|\d{8,15})$')  # SA local or E.164 digits
NAME_PART_RE = re.compile(r'^[\u0600-\u06FFa-zA-Z][\u0600-\u06FFa-zA-Z\s\'-]{0,39}$')
GENDER_VALUES = {'male', 'female'}
CONN_TYPES = {'wifi', 'cellular', 'ethernet', 'unknown'}


def create_app(settings: Settings | None = None) -> Flask:
    cfg = settings or load_settings()
    database = Database(cfg.db)
    database.seed_admin(
        phone=os.getenv('SMARTCARE_ADMIN_PHONE', '0552515874'),
        password=os.getenv('SMARTCARE_ADMIN_PASSWORD', '123456'),
        name=os.getenv('SMARTCARE_ADMIN_NAME', 'مدير النظام'),
    )
    # Rich Hail demo: users + measurements across districts (idempotent).
    # Disable with SMARTCARE_SEED_DEMO=0 — force rebuild with SMARTCARE_SEED_DEMO_FORCE=1
    if os.getenv('SMARTCARE_SEED_DEMO', '1') != '0' and not cfg.testing:
        try:
            demo_summary = seed_demo_hail(
                database, force=os.getenv('SMARTCARE_SEED_DEMO_FORCE') == '1'
            )
            print_demo_credentials(demo_summary)
        except Exception as exc:
            print(f'[smartcare] demo seed skipped: {exc}', flush=True)
    database.cleanup()
    if not cfg.testing:
        persistent = database.persistence_ok()
        print(
            f'[smartcare] db={cfg.db} users={database.user_count()} '
            f'persistent={"yes" if persistent else "NO — accounts will reset on deploy/spin-down; use Render Starter + disk at /var/data"}',
            flush=True,
        )

    app = Flask(
        __name__,
        template_folder='templates',
        static_folder='static',
        static_url_path='/static',
    )
    app.config['SECRET_KEY'] = cfg.secret_key
    app.config['JSON_AS_ASCII'] = False
    app.config['MAX_CONTENT_LENGTH'] = 2 * MIB + 4096
    app.config['PERMANENT_SESSION_LIFETIME'] = timedelta(seconds=SESSION_TTL_SECONDS)
    app.config['SESSION_COOKIE_HTTPONLY'] = True
    app.config['SESSION_COOKIE_SAMESITE'] = 'Lax'
    # Secure cookies are dropped over plain HTTP (local / LAN runs), which breaks web login.
    cookie_secure = os.getenv(
        'SMARTCARE_COOKIE_SECURE',
        '1' if cfg.public_origin.startswith('https://') else '0',
    ) == '1'
    app.config['SESSION_COOKIE_SECURE'] = cookie_secure and not cfg.testing
    app.config['SESSION_REFRESH_EACH_REQUEST'] = True

    sessions: dict = {}
    lock = threading.Lock()
    limits: dict = defaultdict(deque)
    download_payload = os.urandom(2 * MIB)

    # Compatibility with existing pytest suite (app.state.database / test_sessions).
    app.state = SimpleNamespace(database=database, test_sessions=sessions)
    app.extensions['smartcare'] = {'database': database, 'sessions': sessions, 'cfg': cfg}

    CORS(
        app,
        resources={r'/api/*': {'origins': list(cfg.cors_origins)}},
        methods=['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
        allow_headers=['Authorization', 'Content-Type', 'X-Test-Session', 'Cache-Control'],
        expose_headers=['Content-Length', 'Content-Encoding'],
        max_age=600,
        supports_credentials=False,
    )

    def loopback_origin(origin):
        host = urlsplit(origin or 'http://localhost').hostname
        return host in ('localhost', '127.0.0.1', '::1', '10.0.2.2')

    def speed_available():
        if cfg.testing:
            return True
        if not cfg.speed_enabled:
            return False
        if loopback_origin(cfg.public_origin):
            return True
        url = urlsplit(cfg.public_origin)
        if (
            url.scheme != 'https'
            or not url.hostname
            or url.username
            or url.password
            or url.path not in ('', '/')
        ):
            return False
        try:
            addresses = socket.getaddrinfo(url.hostname, 443, type=socket.SOCK_STREAM)
            return bool(addresses) and all(
                ipaddress.ip_address(a[4][0]).is_global for a in addresses
            )
        except OSError:
            return False

    available = speed_available()
    local_speed = available and not cfg.testing and loopback_origin(cfg.public_origin)
    # Loopback can move the whole 32 MiB budget in well under 0.25 s.
    min_phase_seconds = 0.02 if local_speed else 0.25

    stop_retention = threading.Event()

    def retention_loop():
        while not stop_retention.wait(6 * 3600):
            try:
                database.cleanup()
            except sqlite3.Error:
                pass

    threading.Thread(target=retention_loop, name='retention', daemon=True).start()

    def current_lang() -> str:
        """Explicit ?lang, then the web cookie, then X-Lang; the app (no cookie) stays Arabic."""
        if 'lang' not in g:
            g.lang = (
                normalize_lang(request.args.get('lang'))
                or normalize_lang(request.cookies.get(LANG_COOKIE))
                or normalize_lang(request.headers.get('X-Lang'))
                or DEFAULT_LANG
            )
        return g.lang

    def tr(text: str, **params) -> str:
        return translate(text, current_lang(), **params)

    def safe_next(target, fallback):
        if (
            isinstance(target, str)
            and target.startswith('/')
            and not target.startswith('//')
            and '\\' not in target
        ):
            return target
        return fallback

    def api_error(status: int, detail: str):
        return jsonify({'detail': tr(detail)}), status

    def throttle(key, count, seconds):
        now = time.monotonic()
        with lock:
            entries = limits[key]
            while entries and entries[0] < now - seconds:
                entries.popleft()
            if len(entries) >= count:
                raise _ApiError(429, 'طلبات كثيرة؛ حاول لاحقًا')
            entries.append(now)
            if len(limits) > 20000:
                for k in list(limits):
                    if not limits[k] or limits[k][-1] < now - 3600:
                        del limits[k]

    class _ApiError(Exception):
        def __init__(self, status, detail, **params):
            self.status = status
            self.detail = detail
            self.params = params

        def message(self) -> str:
            return tr(self.detail, **self.params)

    @app.errorhandler(_ApiError)
    def handle_api_error(err: _ApiError):
        return jsonify({'detail': err.message()}), err.status

    @app.errorhandler(HTTPException)
    def handle_http(err: HTTPException):
        if request.path.startswith('/api/'):
            return api_error(err.code or 500, err.description or 'خطأ')
        return err

    @app.before_request
    def guard():
        origin = request.headers.get('origin')
        if (
            origin
            and origin not in cfg.cors_origins
            and request.path.startswith('/api/')
            and urlsplit(origin).netloc != request.host
        ):
            return Response(status=403)
        if request.method != 'OPTIONS' and request.path.startswith('/api/'):
            try:
                throttle(
                    ('ip', request.remote_addr or '0.0.0.0'),
                    2000 if (cfg.testing or cfg.speed_enabled) else 180,
                    60,
                )
            except _ApiError as exc:
                return Response(status=exc.status)
        length = request.headers.get('content-length', '0')
        try:
            max_body = 2 * MIB if request.path == '/api/speed/upload' else 16384
            if request.path.startswith('/api/') and (
                int(length) < 0 or int(length) > max_body
            ):
                return Response(status=413)
        except ValueError:
            return Response(status=400)
        if (
            request.method in ('POST', 'PUT', 'DELETE')
            and request.path.startswith('/api/')
            and request.path != '/api/speed/upload'
        ):
            data = request.get_data(cache=True, as_text=False)
            if len(data) > 16384:
                return Response(status=413)

    @app.after_request
    def secure_headers(response):
        response.headers['Cache-Control'] = 'no-store, no-cache, max-age=0'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        chosen = normalize_lang(request.args.get('lang'))
        if chosen and not request.path.startswith('/api/'):
            set_lang_cookie(response, chosen)
        return response

    def set_lang_cookie(response, code):
        response.set_cookie(
            LANG_COOKIE,
            code,
            max_age=365 * 24 * 60 * 60,
            samesite='Lax',
            secure=app.config['SESSION_COOKIE_SECURE'],
        )

    def touch_session(token_hash: str):
        """Extend server session on activity so logout is the only disconnect."""
        expires = time.time() + SESSION_TTL_SECONDS
        with database.connect() as db:
            db.execute(
                'UPDATE auth_sessions SET expires=? WHERE token_hash=?',
                (expires, token_hash),
            )
        if session.get('api_token'):
            session.permanent = True
            session['expires_at'] = expires
        return expires

    def current_user(required=True):
        auth = request.headers.get('authorization', '')
        token = None
        if auth.startswith('Bearer '):
            token = auth[7:]
        elif session.get('api_token'):
            expires_at = session.get('expires_at')
            if expires_at and float(expires_at) < time.time():
                session.clear()
                if required:
                    raise _ApiError(401, 'انتهت الجلسة؛ سجّل الدخول مجددًا')
                return None
            token = session['api_token']
        if not token:
            if required:
                raise _ApiError(401, 'يلزم تسجيل الدخول بالخادم')
            return None
        digest = hashlib.sha256(token.encode()).hexdigest()
        with database.connect() as db:
            db.execute('DELETE FROM auth_sessions WHERE expires < ?', (time.time(),))
            row = db.execute(
                '''SELECT u.id,u.name,u.phone,u.is_admin,u.first_name,u.second_name,u.family_name,u.gender,
                          COALESCE(u.phone_verified,0) AS phone_verified
                   FROM auth_sessions s JOIN users u ON u.id=s.user_id
                   WHERE s.token_hash=? AND s.expires>?''',
                (digest, time.time()),
            ).fetchone()
        if not row:
            session.clear()
            if required:
                raise _ApiError(401, 'انتهت الجلسة؛ سجّل الدخول مجددًا')
            return None
        touch_session(digest)
        user = dict(row)
        user['is_admin'] = bool(user.get('is_admin'))
        user['_token'] = token
        return user

    def require_admin(user):
        if not user.get('is_admin'):
            raise _ApiError(403, 'هذه الصفحة للمدير فقط')
        return user

    def public_user(user):
        return {
            'id': user['id'],
            'name': user.get('name') or 'مستخدم SmartCare',
            'phone': user['phone'],
            'is_admin': bool(user.get('is_admin')),
            'first_name': user.get('first_name') or '',
            'second_name': user.get('second_name') or '',
            'family_name': user.get('family_name') or '',
            'gender': user.get('gender') or '',
            'phone_verified': bool(user.get('phone_verified')),
        }

    def issue_token(user):
        token = secrets.token_urlsafe(32)
        expires = time.time() + SESSION_TTL_SECONDS
        with database.connect() as db:
            db.execute('DELETE FROM auth_sessions WHERE expires < ?', (time.time(),))
            db.execute(
                'INSERT INTO auth_sessions VALUES(?,?,?)',
                (
                    hashlib.sha256(token.encode()).hexdigest(),
                    user['id'],
                    expires,
                ),
            )
        verified = bool(user.get('phone_verified'))
        return {
            'token': token,
            'user': public_user(user),
            'expires_in': SESSION_TTL_SECONDS,
            'expires_at': expires,
            'phone_verified': verified,
        }

    def get_app_setting(key: str) -> str:
        with database.connect() as db:
            row = db.execute(
                'SELECT value FROM app_settings WHERE key=?', (key,)
            ).fetchone()
        return (row['value'] if row and row['value'] else '') or ''

    def set_app_setting(key: str, value: str):
        with database.connect() as db:
            db.execute(
                '''INSERT INTO app_settings(key,value,updated_at) VALUES(?,?,?)
                   ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at''',
                (key, value, time.time()),
            )

    def whatsapp_otp_config():
        return green_config_from_env_and_db(get_app_setting)

    def hash_otp(phone: str, purpose: str, code: str) -> str:
        material = f'{phone}|{purpose}|{code}|{cfg.secret_key}'.encode()
        return hashlib.sha256(material).hexdigest()

    def resolve_phone_fields(body, *, require_country_for_new=False):
        """Normalize phone from country + national number (or legacy 05…)."""
        if not isinstance(body, dict):
            raise _ApiError(422, 'حقول غير صالحة؛ أدخل رقم الجوال وكلمة المرور')
        raw = body.get('phone', '')
        if not isinstance(raw, str):
            raise _ApiError(422, 'رقم الجوال غير صالح')
        raw = raw.strip()
        country_iso = (body.get('country_code') or body.get('country') or '').strip().upper()
        # Login with stored SA number still works without country picker.
        if not country_iso and PHONE_RE.match(raw):
            return raw, 'SA'
        if not country_iso:
            if require_country_for_new:
                raise _ApiError(422, 'اختر الدولة')
            # Accept already-stored E.164 / legacy values for login OTP
            digits = re.sub(r'\D+', '', raw)
            if PHONE_STORAGE_RE.match(digits):
                iso = 'SA' if PHONE_RE.match(digits) else ''
                return digits, iso or 'SA'
            raise _ApiError(422, 'رقم الجوال غير صالح؛ اختر الدولة وأدخل الرقم المحلي')
        if not get_country(country_iso):
            raise _ApiError(422, 'الدولة غير مدعومة')
        try:
            storage, _e164, iso = validate_and_store_phone(country_iso, raw)
        except ValueError:
            raise _ApiError(
                422,
                'رقم الجوال غير صالح لهذه الدولة؛ راجع الصيغة بجانب العلم',
            )
        return storage, iso

    def parse_phone_password(body, allowed_extra=frozenset(), *, require_country=False):
        if not isinstance(body, dict):
            raise _ApiError(422, 'حقول غير صالحة؛ أدخل رقم الجوال وكلمة المرور')
        password = body.get('password', '')
        phone, country_iso = resolve_phone_fields(
            body, require_country_for_new=require_country
        )
        if not isinstance(password, str) or not (6 <= len(password) <= 128):
            raise _ApiError(422, 'كلمة المرور من 6 إلى 128 حرفًا')
        extra = set(body) - (
            {'phone', 'password', 'country_code', 'country'} | set(allowed_extra)
        )
        if extra:
            raise _ApiError(422, 'حقول غير صالحة في الطلب')
        return phone, password, country_iso

    def require_strong_password(password: str) -> str:
        if not isinstance(password, str) or len(password) > 128:
            raise _ApiError(
                422,
                'كلمة المرور يجب أن تكون 8 أحرف على الأقل وتشمل حرفًا كبيرًا ورقمًا ورمزًا',
            )
        ok = (
            len(password) >= 8
            and re.search(r'[A-Z]', password)
            and re.search(r'\d', password)
            and re.search(r'[^A-Za-z0-9]', password)
        )
        if not ok:
            raise _ApiError(
                422,
                'كلمة المرور يجب أن تكون 8 أحرف على الأقل وتشمل حرفًا كبيرًا ورقمًا ورمزًا',
            )
        return password

    def parse_name_part(value, label):
        if not isinstance(value, str):
            raise _ApiError(422, '{label} غير صالح', label=label)
        part = ' '.join(value.split())
        if not NAME_PART_RE.match(part):
            raise _ApiError(
                422, 'أدخل {label} بحروف عربية أو إنجليزية (حتى 40 حرفًا)', label=label
            )
        return part

    def parse_register(body):
        phone, password, country_iso = parse_phone_password(
            body,
            allowed_extra=frozenset(
                {
                    'first_name',
                    'second_name',
                    'family_name',
                    'gender',
                    'name',
                    'code',
                    'purpose',
                }
            ),
            require_country=True,
        )
        password = require_strong_password(password)
        first = parse_name_part(body.get('first_name', ''), 'الاسم الأول')
        second = parse_name_part(body.get('second_name', ''), 'الاسم الثاني')
        family = parse_name_part(body.get('family_name', ''), 'اسم العائلة')
        gender = body.get('gender', '')
        if not isinstance(gender, str):
            gender = ''
        if gender and gender not in GENDER_VALUES:
            gender = ''
        full_name = f'{first} {second} {family}'.strip()
        if len(full_name) > 120:
            raise _ApiError(422, 'الاسم الكامل طويل جدًا')
        return {
            'phone': phone,
            'password': password,
            'country_code': country_iso,
            'first_name': first,
            'second_name': second,
            'family_name': family,
            'gender': gender,
            'name': full_name,
        }

    def parse_credentials(body):
        """Legacy helper: login fields only (phone + password)."""
        phone, password, _iso = parse_phone_password(
            body, allowed_extra=frozenset({'name'})
        )
        name = body.get('name', '') or ''
        if not isinstance(name, str) or len(name) > 80:
            raise _ApiError(422, 'حقول غير صالحة')
        return phone, password, name.strip()

    def get_test(user):
        sid = request.headers.get('x-test-session', '')
        s = sessions.get(sid)
        if not s or s['user'] != user['id'] or time.monotonic() - s['started'] > 120 or s['used']:
            raise _ApiError(409, 'جلسة قياس غير صالحة أو منتهية')
        return s

    def query_map():
        q = request.args
        try:
            now = time.time()
            start = float(q.get('start', now - 7 * 86400))
            end = float(q.get('end', now))
            bbox = [
                float(v)
                for v in q.get('bbox', ','.join(map(str, QUALITY['bounds']))).split(',')
            ]
            minimum = int(q.get('min_samples', QUALITY['min_samples']))
            min_download = float(q.get('min_download', 0))
            max_ping = float(q.get('max_ping', 10000))
            if len(bbox) != 4 or not all(
                math.isfinite(v) for v in bbox + [start, end, min_download, max_ping]
            ) or not (
                -180 <= bbox[0] < bbox[2] <= 180 and -90 <= bbox[1] < bbox[3] <= 90
            ):
                raise ValueError()
            if (
                not 0 < end - start <= 90 * 86400
                or end > now + 60
                or not 0 <= min_download <= 10000
                or not 0 < max_ping <= 10000
                or not QUALITY['min_samples'] <= minimum <= 100
            ):
                raise ValueError()
        except (ValueError, TypeError):
            raise _ApiError(422, 'الفترة أو الحدود أو الفلاتر غير صالحة')
        metric = q.get('metric', 'download')
        connection = q.get('connection', 'all')
        if (
            metric not in ('download', 'upload', 'ping', 'density')
            or connection not in ('all', 'wifi', 'cellular', 'ethernet', 'unknown')
            or q.get('carrier', 'all') != 'all'
        ):
            raise _ApiError(422, 'فلتر غير مدعوم؛ بيانات شركة الاتصالات غير متاحة')
        database.cleanup()
        step = QUALITY['cell_degrees']
        sql = 'SELECT * FROM network_measurements WHERE cell_y IS NOT NULL AND measurement_time BETWEEN ? AND ? AND cell_x BETWEEN ? AND ? AND cell_y BETWEEN ? AND ? AND download_mbps>=? AND ping_ms<=?'
        args = [
            start,
            end,
            math.floor(bbox[0] / step),
            math.floor(bbox[2] / step),
            math.floor(bbox[1] / step),
            math.floor(bbox[3] / step),
            min_download,
            max_ping,
        ]
        if connection != 'all':
            sql += ' AND connection_type=?'
            args.append(connection)
        with database.connect() as db:
            rows = db.execute(sql + ' ORDER BY measurement_time DESC LIMIT 50001', args).fetchall()
        if len(rows) > 50000:
            raise _ApiError(413, 'نطاق كبير؛ ضيق الفترة أو حدود العرض')
        groups = defaultdict(list)
        for row in rows:
            groups[(row['cell_y'], row['cell_x'])].append(row)
        output = []
        for (y, x), items in groups.items():
            if len(set(r['user_id'] for r in items)) < QUALITY['min_contributors']:
                continue
            latest = max(r['measurement_time'] for r in items)
            n = len(items)
            sufficient = n >= minimum
            stale = now - latest > QUALITY['stale_hours'] * 3600
            cell = {
                'id': cell_id(y, x),
                'bounds': cell_bounds(y, x),
                'name': None,
                'sample_count': n if sufficient else None,
                'status': 'insufficient'
                if not sufficient
                else 'stale'
                if stale
                else 'ready',
                'last_measurement': latest if sufficient else None,
                'age_hours': round((now - latest) / 3600, 1) if sufficient else None,
                'confidence': 'adequate_sample' if sufficient and not stale else 'limited',
                'statistics': None,
                'quality': None,
                'carrier': None,
            }
            if sufficient:
                stats = {}
                for key in ('download_mbps', 'upload_mbps', 'ping_ms'):
                    values = [r[key] for r in items]
                    stats[key] = {
                        'mean': round(statistics.mean(values), 3),
                        'median': round(statistics.median(values), 3),
                    }
                stats.update(jitter_ms=None, packet_loss_percent=None)
                cell['statistics'] = stats
                cell['quality'] = {
                    k: classify(stats[v]['median'], k) if not stale else 'stale'
                    for k, v in [
                        ('download', 'download_mbps'),
                        ('upload', 'upload_mbps'),
                        ('ping', 'ping_ms'),
                    ]
                }
                cell['connections'] = sorted(set(r['connection_type'] for r in items))
            output.append(cell)
        return {
            'cells': output,
            'generated_at': now,
            'start': start,
            'end': end,
            'min_samples': minimum,
            'metric': metric,
            'quality_version': QUALITY['version'],
            'suppression': 'Cells with fewer than three contributors are not returned; counts are hidden until sample minimum is met.',
        }

    # ─── API routes ─────────────────────────────────────────────

    def get_stored_gemini_key() -> str:
        with database.connect() as db:
            row = db.execute(
                "SELECT value FROM app_settings WHERE key='gemini_api_key'"
            ).fetchone()
        stored = (row['value'] if row and row['value'] else '') or ''
        return stored.strip() or default_gemini_api_key()

    def run_gemini_analysis(text: str) -> dict:
        api_key = get_stored_gemini_key()
        if not api_key:
            raise _ApiError(
                400,
                'لم يضبط المدير مفتاح Gemini بعد؛ احفظه مرة واحدة من لوحة الإدارة',
            )
        payload = {
            'contents': [
                {
                    'parts': [
                        {
                            'text': GEMINI_INSTRUCTIONS[current_lang()] + '\n\n' + text
                        }
                    ]
                }
            ]
        }
        base = 'https://generativelanguage.googleapis.com/v1beta'

        def model_id(name: str) -> str:
            return name.split('/', 1)[-1] if name else ''

        def preferred_models(available_models: list[str]) -> list[str]:
            rank = [
                'gemini-flash-latest',
                'gemini-2.5-flash',
                'gemini-2.5-flash-lite',
                'gemini-2.0-flash',
                'gemini-2.0-flash-lite',
                'gemini-3.8-flash',
                'gemini-3.6-flash',
                'gemini-3.5-flash-lite',
                'gemini-pro-latest',
            ]
            ordered = [m for m in rank if m in available_models]
            for m in available_models:
                if (
                    m not in ordered
                    and 'flash' in m
                    and 'image' not in m
                    and 'tts' not in m
                ):
                    ordered.append(m)
            for m in available_models:
                if m not in ordered and 'gemini' in m and 'embed' not in m:
                    ordered.append(m)
            return ordered or list(available_models)

        try:
            listed = httpx.get(
                f'{base}/models',
                params={'key': api_key, 'pageSize': 100},
                timeout=30,
            )
        except httpx.HTTPError:
            raise _ApiError(502, 'تعذر الاتصال بخدمة Gemini')
        if listed.status_code >= 400:
            detail, params = 'مفتاح Gemini مرفوض أو غير صالح', {}
            try:
                err = listed.json().get('error', {}).get('message')
                if err:
                    detail, params = 'رفض Gemini: {error}', {'error': err}
            except Exception:
                pass
            raise _ApiError(502, detail, **params)

        available_models = []
        try:
            for item in listed.json().get('models', []):
                methods = (
                    item.get('supportedGenerationMethods')
                    or item.get('supported_generation_methods')
                    or []
                )
                if 'generateContent' not in methods:
                    continue
                mid = model_id(item.get('name', ''))
                if mid:
                    available_models.append(mid)
        except Exception:
            available_models = []

        models = preferred_models(available_models) or [
            'gemini-flash-latest',
            'gemini-2.5-flash',
            'gemini-2.5-flash-lite',
            'gemini-2.0-flash',
        ]

        last_body = None
        used_model = None
        try:
            for model in models:
                response = httpx.post(
                    f'{base}/models/{model}:generateContent',
                    params={'key': api_key},
                    json=payload,
                    timeout=45,
                )
                last_body = response
                used_model = model
                if response.status_code < 400:
                    break
            else:
                detail, params = 'لا يوجد نموذج Gemini متاح لهذا المفتاح', {}
                try:
                    err = last_body.json().get('error', {}).get('message')
                    if err:
                        detail, params = 'رفض Gemini: {error}', {'error': err}
                except Exception:
                    pass
                raise _ApiError(502, detail, **params)
        except httpx.HTTPError:
            raise _ApiError(502, 'تعذر الاتصال بخدمة Gemini')
        try:
            analysis = last_body.json()['candidates'][0]['content']['parts'][0]['text']
        except (KeyError, IndexError, TypeError):
            raise _ApiError(502, 'استجابة Gemini غير صالحة')
        return {'analysis': analysis, 'model': used_model}

    @app.get('/api/network-config')
    def network_config():
        gemini_on = bool(get_stored_gemini_key())
        return jsonify(
            {
                'quality': QUALITY,
                'test': {
                    'available': available,
                    'mode': 'integration_test'
                    if cfg.testing
                    else 'local'
                    if local_speed
                    else 'internet',
                    'reason': None
                    if available
                    else tr('لم يُضبط خادم قياس عام عبر HTTPS؛ اختبار الإنترنت غير متاح'),
                    'server_id': cfg.public_origin
                    or ('http://localhost:8765' if local_speed else 'unconfigured'),
                    'max_bytes': 64 * MIB,
                    'max_seconds': 90,
                    'phase_max_bytes': 32 * MIB,
                    'target_seconds': 6,
                    'min_phase_seconds': min_phase_seconds,
                },
                'ai': {
                    'available': gemini_on,
                    'reason': None
                    if gemini_on
                    else tr('المدير لم يحفظ مفتاح Gemini في الخادم بعد'),
                },
                'carrier': {
                    'available': False,
                    'reason': tr('لا يوجد مصدر موثوق لتحديد شركة الاتصالات؛ لا يتم تخمينها'),
                },
                'privacy': {
                    'min_contributors': QUALITY['min_contributors'],
                    'retention_days': QUALITY['retention_days'],
                    'location': 'cell_only',
                    'auth': 'password_accounts_phone_unverified',
                },
                'whatsapp_otp': {
                    'available': bool(whatsapp_otp_config().get('enabled')),
                    'provider': 'green-api',
                },
            }
        )

    def insert_user(profile, password, *, is_admin=0):
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac(
            'sha256', password.encode(), bytes.fromhex(salt), 600000
        ).hex()
        country_iso = (profile.get('country_code') or 'SA').upper()
        user = {
            'id': secrets.token_urlsafe(18),
            'name': profile['name'],
            'phone': profile['phone'],
            'first_name': profile.get('first_name', ''),
            'second_name': profile.get('second_name', ''),
            'family_name': profile.get('family_name', ''),
            'gender': profile.get('gender', ''),
            'country_code': country_iso,
            'is_admin': bool(is_admin),
        }
        with database.connect() as db:
            db.execute(
                '''INSERT INTO users(
                    id,phone,name,first_name,second_name,family_name,gender,
                    salt,password_hash,hash_iterations,is_admin,created_at,country_code
                   ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                (
                    user['id'],
                    user['phone'],
                    user['name'],
                    user['first_name'],
                    user['second_name'],
                    user['family_name'],
                    user['gender'],
                    salt,
                    digest,
                    600000,
                    1 if is_admin else 0,
                    time.time(),
                    country_iso,
                ),
            )
        return user

    @app.post('/api/auth/register')
    def register():
        throttle(
            ('auth', request.remote_addr or '0'),
            40 if (cfg.testing or cfg.speed_enabled) else 8,
            900,
        )
        body = request.get_json(silent=True) or {}
        profile = parse_register(body)
        try:
            user = insert_user(profile, profile['password'])
        except sqlite3.IntegrityError:
            raise _ApiError(409, 'هذا الرقم مسجّل مسبقًا؛ سجّل الدخول بالرقم وكلمة المرور')
        return jsonify(issue_token(user)), 201

    @app.post('/api/auth/login')
    def login():
        throttle(
            ('auth', request.remote_addr or '0'),
            40 if (cfg.testing or cfg.speed_enabled) else 8,
            900,
        )
        body = request.get_json(silent=True) or {}
        phone, password, _iso = parse_phone_password(body)
        with database.connect() as db:
            row = db.execute('SELECT * FROM users WHERE phone=?', (phone,)).fetchone()
        salt = bytes.fromhex(row['salt']) if row else bytes(16)
        digest = hashlib.pbkdf2_hmac(
            'sha256',
            password.encode(),
            salt,
            row['hash_iterations'] if row else 600000,
        ).hex()
        if not row or not hmac.compare_digest(digest, row['password_hash']):
            raise _ApiError(401, 'رقم الجوال أو كلمة المرور غير صحيحة')
        if row['hash_iterations'] < 600000:
            upgraded = hashlib.pbkdf2_hmac(
                'sha256', password.encode(), salt, 600000
            ).hex()
            with database.connect() as db:
                db.execute(
                    'UPDATE users SET password_hash=?,hash_iterations=600000 WHERE id=?',
                    (upgraded, row['id']),
                )
        return jsonify(issue_token(dict(row)))

    @app.get('/api/auth/me')
    def auth_me():
        user = current_user()
        return jsonify(
            {
                'user': public_user(user),
                'expires_in': SESSION_TTL_SECONDS,
            }
        )

    @app.get('/api/auth/whatsapp/status')
    def whatsapp_otp_status():
        cfg_wa = whatsapp_otp_config()
        return jsonify(
            {
                'available': bool(cfg_wa.get('enabled')),
                'provider': 'green-api',
                'countries': countries_public(current_lang()),
                'default_country': 'SA',
                'reason': None
                if cfg_wa.get('enabled')
                else tr('لم يُضبط GREEN API بعد؛ احفظ المعرّف والتوكن من لوحة الإدارة أو .env'),
            }
        )

    @app.get('/api/auth/countries')
    def auth_countries():
        return jsonify(
            {
                'countries': countries_public(current_lang()),
                'default_country': 'SA',
            }
        )

    @app.post('/api/auth/whatsapp/send-code')
    def whatsapp_send_code():
        throttle(('wa_otp_ip', request.remote_addr or '0'), 20, 900)
        body = request.get_json(silent=True) or {}
        purpose = (body.get('purpose') or 'register').strip()
        if purpose not in ('register', 'reset'):
            raise _ApiError(422, 'غرض التحقق غير صالح')
        phone, country_iso = resolve_phone_fields(
            body, require_country_for_new=(purpose == 'register')
        )
        throttle(('wa_otp_phone', phone), 5, 3600)
        cfg_wa = whatsapp_otp_config()
        if not cfg_wa.get('enabled'):
            raise _ApiError(
                503,
                'لم يُضبط GREEN API بعد؛ احفظ المعرّف والتوكن من لوحة الإدارة أو .env',
            )

        with database.connect() as db:
            exists = db.execute(
                'SELECT id, country_code FROM users WHERE phone=?', (phone,)
            ).fetchone()
            if purpose == 'register' and exists:
                raise _ApiError(
                    409, 'هذا الرقم مسجّل مسبقًا؛ سجّل الدخول بالرقم وكلمة المرور'
                )
            if purpose == 'reset' and not exists:
                raise _ApiError(404, 'لا يوجد حساب بهذا الرقم؛ أنشئ حسابًا أولًا')
            if purpose == 'reset' and exists and exists['country_code']:
                country_iso = exists['country_code'] or country_iso
            recent = db.execute(
                '''SELECT created_at FROM whatsapp_otps
                   WHERE phone=? AND purpose=? AND consumed_at IS NULL
                   ORDER BY created_at DESC LIMIT 1''',
                (phone, purpose),
            ).fetchone()
            if recent and time.time() - float(recent['created_at']) < 55:
                raise _ApiError(429, 'انتظر قليلًا قبل طلب رمز جديد')

        code = f'{secrets.randbelow(1_000_000):06d}'
        otp_id = secrets.token_urlsafe(14)
        now = time.time()
        expires = now + 300
        with database.connect() as db:
            db.execute(
                '''INSERT INTO whatsapp_otps(
                     id,phone,purpose,code_hash,expires_at,attempts,created_at,consumed_at,ip
                   ) VALUES(?,?,?,?,?,0,?,NULL,?)''',
                (
                    otp_id,
                    phone,
                    purpose,
                    hash_otp(phone, purpose, code),
                    expires,
                    now,
                    (request.remote_addr or '')[:64],
                ),
            )
        try:
            send_whatsapp_text(
                api_url=cfg_wa['api_url'],
                id_instance=cfg_wa['id_instance'],
                token_instance=cfg_wa['token_instance'],
                phone=phone,
                country_iso=country_iso,
                message=otp_message_ar(code, purpose),
            )
        except Exception as exc:
            with database.connect() as db:
                db.execute('DELETE FROM whatsapp_otps WHERE id=?', (otp_id,))
            raise _ApiError(502, 'تعذر إرسال واتساب عبر GREEN API: {error}', error=str(exc)[:160])

        payload = {
            'ok': True,
            'phone': phone,
            'country_code': country_iso,
            'purpose': purpose,
            'expires_in': 300,
            'message': tr('تم إرسال رمز التحقق عبر واتساب'),
        }
        # Never expose OTP in production responses; only while testing.
        if cfg.testing:
            payload['debug_code'] = code
        return jsonify(payload)

    @app.post('/api/auth/whatsapp/verify')
    def whatsapp_verify_code():
        throttle(('wa_verify_ip', request.remote_addr or '0'), 40, 900)
        body = request.get_json(silent=True) or {}
        purpose = (body.get('purpose') or 'register').strip()
        code = (body.get('code') or '').strip()
        if purpose not in ('register', 'reset'):
            raise _ApiError(422, 'غرض التحقق غير صالح')
        phone, country_iso = resolve_phone_fields(
            body, require_country_for_new=(purpose == 'register')
        )
        if not re.fullmatch(r'\d{6}', code or ''):
            raise _ApiError(422, 'رمز التحقق يجب أن يكون 6 أرقام')

        now = time.time()
        reset_user = None
        with database.connect() as db:
            row = db.execute(
                '''SELECT * FROM whatsapp_otps
                   WHERE phone=? AND purpose=? AND consumed_at IS NULL
                   ORDER BY created_at DESC LIMIT 1''',
                (phone, purpose),
            ).fetchone()
            if not row or float(row['expires_at']) < now:
                raise _ApiError(401, 'رمز التحقق منتهٍ أو غير موجود؛ اطلب رمزًا جديدًا')
            if int(row['attempts'] or 0) >= 5:
                raise _ApiError(429, 'محاولات كثيرة؛ اطلب رمزًا جديدًا')
            expected = hash_otp(phone, purpose, code)
            if not hmac.compare_digest(expected, row['code_hash']):
                db.execute(
                    'UPDATE whatsapp_otps SET attempts=attempts+1 WHERE id=?',
                    (row['id'],),
                )
                raise _ApiError(401, 'رمز التحقق غير صحيح')
            db.execute(
                'UPDATE whatsapp_otps SET consumed_at=?, attempts=attempts+1 WHERE id=?',
                (now, row['id']),
            )
            if purpose == 'reset':
                user_row = db.execute(
                    'SELECT * FROM users WHERE phone=?', (phone,)
                ).fetchone()
                if not user_row:
                    raise _ApiError(404, 'لا يوجد حساب بهذا الرقم؛ أنشئ حسابًا أولًا')
                reset_user = dict(user_row)

        if purpose == 'reset':
            new_password = require_strong_password(body.get('password', ''))
            salt = secrets.token_hex(16)
            digest = hashlib.pbkdf2_hmac(
                'sha256', new_password.encode(), bytes.fromhex(salt), 600000
            ).hex()
            with database.connect() as db:
                db.execute(
                    '''UPDATE users
                       SET salt=?, password_hash=?, hash_iterations=600000, phone_verified=1
                       WHERE id=?''',
                    (salt, digest, reset_user['id']),
                )
            reset_user['phone_verified'] = 1
            result = issue_token(reset_user)
            session.clear()
            session.permanent = True
            session['api_token'] = result['token']
            session['user'] = result['user']
            session['expires_at'] = result['expires_at']
            return jsonify(result)

        try:
            profile = parse_register(body)
        except _ApiError:
            raise
        if profile['phone'] != phone:
            raise _ApiError(422, 'رقم الجوال لا يطابق طلب التحقق')
        try:
            user = insert_user(profile, profile['password'])
        except sqlite3.IntegrityError:
            raise _ApiError(
                409, 'هذا الرقم مسجّل مسبقًا؛ سجّل الدخول بالرقم وكلمة المرور'
            )
        with database.connect() as db:
            db.execute(
                'UPDATE users SET phone_verified=1 WHERE id=?', (user['id'],)
            )
        user['phone_verified'] = 1
        result = issue_token(user)
        session.clear()
        session.permanent = True
        session['api_token'] = result['token']
        session['user'] = result['user']
        session['expires_at'] = result['expires_at']
        return jsonify(result), 201

    @app.delete('/api/auth/session')
    def logout():
        user = current_user()
        auth = request.headers.get('authorization', '')
        token = auth[7:] if auth.startswith('Bearer ') else session.get('api_token', '')
        if token:
            with database.connect() as db:
                db.execute(
                    'DELETE FROM auth_sessions WHERE token_hash=?',
                    (hashlib.sha256(token.encode()).hexdigest(),),
                )
        session.clear()
        return Response(status=204)

    @app.post('/api/speed/sessions')
    def start_test():
        user = current_user()
        if not available:
            raise _ApiError(503, 'اختبار الإنترنت غير متاح حتى إعداد خادم عام مناسب')
        throttle(
            ('tests', user['id']),
            100 if (cfg.testing or cfg.speed_enabled) else 4,
            3600,
        )
        with lock:
            for key in list(sessions):
                if time.monotonic() - sessions[key]['started'] > 180:
                    del sessions[key]
            sid = secrets.token_urlsafe(24)
            sessions[sid] = {
                'user': user['id'],
                'started': time.monotonic(),
                'download': 0,
                'upload': 0,
                'ping': 0,
                'used': False,
            }
        return jsonify({'session_id': sid, 'max_bytes': 64 * MIB, 'max_seconds': 90}), 201

    @app.get('/api/speed/ping')
    def ping():
        user = current_user()
        s = get_test(user)
        with lock:
            s['ping'] += 1
        return jsonify({'ok': True})

    @app.get('/api/speed/download')
    def download():
        user = current_user()
        s = get_test(user)
        try:
            size = int(request.args.get('size', 2 * MIB))
        except ValueError:
            raise _ApiError(422, 'حجم غير صالح')
        if size < 65536 or size > 2 * MIB:
            raise _ApiError(422, 'حجم غير صالح')
        with lock:
            if s['download'] + size > 32 * MIB:
                raise _ApiError(413, 'انتهت ميزانية التنزيل')
            s['download'] += size
        return Response(
            download_payload[:size],
            mimetype='application/octet-stream',
            headers={
                'Content-Length': str(size),
                'Content-Encoding': 'identity',
                'Cache-Control': 'no-store',
                'X-Accel-Buffering': 'no',
            },
        )

    @app.post('/api/speed/upload')
    def upload():
        user = current_user()
        s = get_test(user)
        if request.headers.get('content-encoding') not in (None, 'identity'):
            raise _ApiError(400, 'لا تقبل بيانات قياس مضغوطة')
        data = request.get_data(cache=False, as_text=False)
        count = len(data)
        if count > 2 * MIB:
            raise _ApiError(413, 'حجم رفع غير مسموح')
        if count < 65536:
            raise _ApiError(422, 'عينة رفع صغيرة جدًا')
        with lock:
            if s['upload'] + count > 32 * MIB:
                raise _ApiError(413, 'انتهت ميزانية الرفع')
            s['upload'] += count
        return jsonify({'received_bytes': count})

    @app.post('/api/network-tests')
    def save_measurement():
        user = current_user()
        data = request.get_json(silent=True) or {}
        try:
            session_id = data['session_id']
            download_mbps = float(data['download_mbps'])
            upload_mbps = float(data['upload_mbps'])
            ping_ms = float(data['ping_ms'])
            download_seconds = float(data['download_seconds'])
            upload_seconds = float(data['upload_seconds'])
            download_bytes = int(data['download_bytes'])
            upload_bytes = int(data['upload_bytes'])
            connection_type = data['connection_type']
            connection_source = data['connection_source']
            share_location = bool(data.get('share_location', False))
            measurement_time = float(data['measurement_time'])
            test_status = data['test_status']
            latitude = data.get('latitude')
            longitude = data.get('longitude')
            location_accuracy_m = data.get('location_accuracy_m')
        except (KeyError, TypeError, ValueError):
            raise _ApiError(
                422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'
            )
        if any(
            not math.isfinite(v)
            for v in (
                download_mbps,
                upload_mbps,
                ping_ms,
                download_seconds,
                upload_seconds,
                measurement_time,
            )
            if v is not None
        ):
            raise _ApiError(
                422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'
            )
        if not (
            isinstance(session_id, str)
            and 20 <= len(session_id) <= 100
            and 0 < download_mbps <= 10000
            and 0 < upload_mbps <= 10000
            and 0 < ping_ms <= 10000
            and min_phase_seconds <= download_seconds <= 90
            and min_phase_seconds <= upload_seconds <= 90
            and 4 * MIB <= download_bytes <= 32 * MIB
            and 4 * MIB <= upload_bytes <= 32 * MIB
            and connection_type in CONN_TYPES
            and connection_source in ('os_interface', 'unavailable')
            and test_status == 'completed'
        ):
            raise _ApiError(
                422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'
            )
        if latitude is not None:
            try:
                latitude = float(latitude)
                if not (-90 <= latitude <= 90) or not math.isfinite(latitude):
                    raise ValueError()
            except (TypeError, ValueError):
                raise _ApiError(
                    422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'
                )
        if longitude is not None:
            try:
                longitude = float(longitude)
                if not (-180 <= longitude <= 180) or not math.isfinite(longitude):
                    raise ValueError()
            except (TypeError, ValueError):
                raise _ApiError(
                    422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'
                )
        if location_accuracy_m is not None:
            try:
                location_accuracy_m = float(location_accuracy_m)
                if not (0 < location_accuracy_m <= 10000) or not math.isfinite(
                    location_accuracy_m
                ):
                    raise ValueError()
            except (TypeError, ValueError):
                raise _ApiError(
                    422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'
                )
        allowed = {
            'session_id',
            'download_mbps',
            'upload_mbps',
            'ping_ms',
            'download_seconds',
            'upload_seconds',
            'download_bytes',
            'upload_bytes',
            'connection_type',
            'connection_source',
            'latitude',
            'longitude',
            'location_accuracy_m',
            'share_location',
            'measurement_time',
            'test_status',
        }
        if set(data) - allowed:
            raise _ApiError(
                422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'
            )
        s = sessions.get(session_id)
        if (
            not available
            or not s
            or s['used']
            or s['user'] != user['id']
            or time.monotonic() - s['started'] > 180
        ):
            raise _ApiError(409, 'نتيجة بلا جلسة نقل بيانات موثقة')
        if (
            s['download'] != download_bytes
            or s['upload'] != upload_bytes
            or s['ping'] < 7
        ):
            raise _ApiError(422, 'لا تتطابق النتيجة مع نقل البيانات على الخادم')
        for rate, byte_count, seconds in [
            (download_mbps, download_bytes, download_seconds),
            (upload_mbps, upload_bytes, upload_seconds),
        ]:
            if not math.isclose(rate, byte_count * 8 / seconds / 1_000_000, rel_tol=0.03):
                raise _ApiError(422, 'معدل النقل لا يطابق الحجم والمدة')
        elapsed = time.monotonic() - s['started']
        if (
            download_seconds + upload_seconds > elapsed + 1
            or abs(measurement_time - time.time()) > 300
        ):
            raise _ApiError(422, 'توقيت القياس غير صالح')
        y = x = None
        if share_location:
            if latitude is None or longitude is None or location_accuracy_m is None:
                raise _ApiError(422, 'مشاركة الخريطة تحتاج موافقة وموقعًا ودقة معلومين')
            # Worldwide cells allowed for testing; Hail remains the default map view only.
            # Cells are ~1 km; allow up to 2 km horizontal accuracy (mobile GPS/network).
            if location_accuracy_m > 2000:
                raise _ApiError(
                    422, 'دقة الموقع غير كافية لتصنيف خلية؛ يمكنك الحفظ دون مشاركة'
                )
            y, x = cell_for(latitude, longitude)
        elif (
            latitude is not None
            or longitude is not None
            or location_accuracy_m is not None
        ):
            raise _ApiError(422, 'لا ترسل موقعًا دون الموافقة على المشاركة')
        if connection_type != 'unknown' and connection_source != 'os_interface':
            raise _ApiError(422, 'نوع الاتصال يحتاج مصدر واجهة الجهاز')
        database.cleanup()
        mid = secrets.token_urlsafe(18)
        try:
            with database.connect() as db:
                db.execute(
                    '''INSERT INTO network_measurements(id,user_id,download_mbps,upload_mbps,ping_ms,connection_type,connection_source,cell_y,cell_x,location_accuracy_m,measurement_time,created_at,test_status,server_id,session_id,hour_bucket) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                    (
                        mid,
                        user['id'],
                        download_mbps,
                        upload_mbps,
                        ping_ms,
                        connection_type,
                        connection_source,
                        y,
                        x,
                        math.ceil(location_accuracy_m / 100) * 100
                        if y is not None
                        else None,
                        measurement_time,
                        time.time(),
                        test_status,
                        cfg.public_origin or 'integration-test',
                        session_id,
                        int(measurement_time // 3600),
                    ),
                )
        except sqlite3.IntegrityError:
            raise _ApiError(409, 'تم تسجيل نتيجة لهذه الخلية خلال الساعة؛ لا تُكرر المساهمات')
        with lock:
            s['used'] = True
        return jsonify(
            {'id': mid, 'shared': y is not None, 'cell_id': cell_id(y, x) if y is not None else None}
        ), 201

    @app.get('/api/network-heatmap')
    def heatmap():
        return jsonify(query_map())

    @app.get('/api/network-heatmap/mine')
    def heatmap_mine():
        user = current_user()
        now = time.time()
        start = now - QUALITY['retention_days'] * 86400
        with database.connect() as db:
            rows = db.execute(
                'SELECT * FROM network_measurements WHERE user_id=? AND cell_y IS NOT NULL AND measurement_time>=? ORDER BY measurement_time DESC LIMIT 5000',
                (user['id'], start),
            ).fetchall()
        groups = defaultdict(list)
        for row in rows:
            groups[(row['cell_y'], row['cell_x'])].append(row)
        output = []
        for (y, x), items in groups.items():
            latest = max(r['measurement_time'] for r in items)
            stats = {}
            for key in ('download_mbps', 'upload_mbps', 'ping_ms'):
                values = [r[key] for r in items]
                stats[key] = {
                    'mean': round(statistics.mean(values), 3),
                    'median': round(statistics.median(values), 3),
                }
            output.append(
                {
                    'id': cell_id(y, x),
                    'bounds': cell_bounds(y, x),
                    'name': None,
                    'sample_count': len(items),
                    'status': 'personal',
                    'last_measurement': latest,
                    'age_hours': round((now - latest) / 3600, 1),
                    'confidence': 'owner_sample',
                    'statistics': stats,
                    'quality': {
                        k: classify(stats[v]['median'], k)
                        for k, v in [
                            ('download', 'download_mbps'),
                            ('upload', 'upload_mbps'),
                            ('ping', 'ping_ms'),
                        ]
                    },
                    'connections': sorted(set(r['connection_type'] for r in items)),
                    'owner': True,
                }
            )
        return jsonify({'cells': output, 'generated_at': now})

    @app.get('/api/network-areas/<area_id>')
    def area_details(area_id):
        result = query_map()
        for cell in result['cells']:
            if cell['id'] == area_id:
                return jsonify({'cell': cell, 'start': result['start'], 'end': result['end']})
        raise _ApiError(404, 'لا توجد بيانات منشورة كافية لهذه الخلية')

    @app.get('/api/network-statistics')
    def statistics_api():
        data = query_map()
        ready = [c for c in data['cells'] if c['status'] == 'ready']
        return jsonify(
            {
                'published_cells': len(data['cells']),
                'ready_cells': len(ready),
                'sample_count': sum(c['sample_count'] or 0 for c in data['cells']),
                'generated_at': data['generated_at'],
                'note': 'Statistics use privacy-filtered cells only; unweighted cell medians are not presented as an overall network average.',
            }
        )

    def _soft_complaint_weight(row) -> float:
        """Weight a measurement as an implicit complaint when quality is weak."""
        dl_q = classify(float(row['download_mbps']), 'download')
        ping_q = classify(float(row['ping_ms']), 'ping')
        score = 0.0
        if dl_q == 'very_poor':
            score += 1.0
        elif dl_q == 'poor':
            score += 0.55
        if ping_q == 'very_poor':
            score += 0.7
        elif ping_q == 'poor':
            score += 0.35
        return min(1.5, score)

    def _avg(vals, default=None):
        return statistics.mean(vals) if vals else default

    def _clamp(v, lo=0.0, hi=1.0):
        return max(lo, min(hi, v))

    def build_outage_radar(bbox=None):
        """Compare recent cell health vs same-hour baseline; raise risk when
        complaints and measurements both degrade."""
        now = time.time()
        recent_h = 3.0
        baseline_days = 14
        recent_start = now - recent_h * 3600
        history_start = now - baseline_days * 86400
        current_hour = datetime.fromtimestamp(now, tz=timezone.utc).hour
        database.cleanup()

        step = QUALITY['cell_degrees']
        meas_sql = (
            'SELECT cell_y,cell_x,download_mbps,upload_mbps,ping_ms,measurement_time,user_id '
            'FROM network_measurements WHERE cell_y IS NOT NULL AND measurement_time >= ?'
        )
        meas_args = [history_start]
        comp_sql = (
            'SELECT cell_y,cell_x,severity,created_at FROM service_complaints '
            'WHERE created_at >= ? AND cell_y IS NOT NULL'
        )
        comp_args = [history_start]
        if bbox and len(bbox) == 4:
            meas_sql += ' AND cell_x BETWEEN ? AND ? AND cell_y BETWEEN ? AND ?'
            meas_args.extend(
                [
                    math.floor(bbox[0] / step),
                    math.floor(bbox[2] / step),
                    math.floor(bbox[1] / step),
                    math.floor(bbox[3] / step),
                ]
            )
            comp_sql += ' AND cell_x BETWEEN ? AND ? AND cell_y BETWEEN ? AND ?'
            comp_args.extend(meas_args[1:])

        with database.connect() as db:
            measurements = db.execute(meas_sql, meas_args).fetchall()
            complaints = db.execute(comp_sql, comp_args).fetchall()

        by_cell_m = defaultdict(list)
        for row in measurements:
            by_cell_m[(row['cell_y'], row['cell_x'])].append(row)
        by_cell_c = defaultdict(list)
        for row in complaints:
            by_cell_c[(row['cell_y'], row['cell_x'])].append(row)

        alerts = []
        viz_cells = []
        for (y, x), items in by_cell_m.items():
            recent = [r for r in items if r['measurement_time'] >= recent_start]
            older = [r for r in items if r['measurement_time'] < recent_start]
            # Always keep a map footprint for cells that have real measurements.
            sample_pool = recent or items[:8]
            if not sample_pool and not by_cell_c.get((y, x)):
                continue

            same_hour = [
                r
                for r in older
                if datetime.fromtimestamp(r['measurement_time'], tz=timezone.utc).hour
                == current_hour
            ]
            baseline = same_hour if len(same_hour) >= 2 else older

            recent_dl = _avg([float(r['download_mbps']) for r in (recent or sample_pool)])
            recent_ping = _avg([float(r['ping_ms']) for r in (recent or sample_pool)])
            base_dl = _avg([float(r['download_mbps']) for r in baseline], recent_dl)
            base_ping = _avg([float(r['ping_ms']) for r in baseline], recent_ping)

            soft_recent = sum(_soft_complaint_weight(r) for r in (recent or sample_pool))
            soft_base = sum(_soft_complaint_weight(r) for r in baseline)
            expl_recent = sum(
                max(1, int(c['severity'] or 1)) * 0.85
                for c in by_cell_c.get((y, x), [])
                if c['created_at'] >= recent_start
            )
            expl_base = sum(
                max(1, int(c['severity'] or 1)) * 0.85
                for c in by_cell_c.get((y, x), [])
                if c['created_at'] < recent_start
            )
            complaints_recent = soft_recent + expl_recent
            baseline_hours = max(1.0, (baseline_days * 24) - recent_h)
            if baseline:
                span = max(
                    1.0,
                    (max(r['measurement_time'] for r in baseline)
                     - min(r['measurement_time'] for r in baseline))
                    / 3600.0,
                )
                baseline_hours = max(span, recent_h)
            expected = (soft_base + expl_base) / baseline_hours * recent_h
            complaint_ratio = complaints_recent / max(expected, 0.45)

            speed_drop = 0.0
            ping_rise = 0.0
            if recent_dl is not None and base_dl and base_dl > 0 and baseline:
                speed_drop = _clamp((base_dl - recent_dl) / base_dl)
            if recent_ping is not None and base_ping and base_ping > 0 and baseline:
                ping_rise = _clamp((recent_ping - base_ping) / base_ping)
            degradation = _clamp(0.55 * speed_drop + 0.45 * ping_rise)
            # Cold start: no baseline yet — use absolute weakness of recent samples.
            if not baseline and (recent or sample_pool):
                abs_weak = sum(
                    _soft_complaint_weight(r) for r in (recent or sample_pool)
                ) / max(len(recent or sample_pool), 1)
                degradation = max(degradation, _clamp(abs_weak / 1.2))

            # Risk rises when complaints spike and quality worsens together.
            joint = _clamp((complaint_ratio - 1.0) / 3.0) * (0.35 + 0.65 * degradation)
            solo = 0.0
            if complaint_ratio >= 2.2:
                solo = max(solo, _clamp((complaint_ratio - 1.0) / 4.0) * 0.75)
            if degradation >= 0.35 and (recent or sample_pool):
                solo = max(solo, degradation * 0.7)
            risk = _clamp(max(joint * 1.35, solo, joint + solo * 0.25))
            # Soft monitor intensity from absolute quality so the map is never blank.
            if recent_dl is not None:
                q = classify(recent_dl, 'download')
                soft_map = {
                    'very_poor': 0.55,
                    'poor': 0.38,
                    'moderate': 0.18,
                    'good': 0.08,
                }
                risk = max(risk, soft_map.get(q, 0.12))

            priority = round(
                max(complaints_recent, 0.2)
                * (1.0 + degradation * 3.0)
                * (0.55 + risk),
                3,
            )
            level = (
                'critical'
                if risk >= 0.75
                else 'high'
                if risk >= 0.55
                else 'watch'
                if risk >= 0.35
                else 'info'
            )
            b = cell_bounds(y, x)
            lat = (b[1] + b[3]) / 2
            lon = (b[0] + b[2]) / 2
            ratio_txt = max(1, round(complaint_ratio))
            parts = []
            if complaint_ratio >= 1.6:
                parts.append(f'الشكاوى زادت ≈{ratio_txt}× عن المعتاد لهذا الوقت')
            if speed_drop >= 0.2 and recent_dl is not None and base_dl is not None:
                parts.append(
                    f'متوسط التحميل انخفض من {base_dl:.0f} إلى {recent_dl:.0f} Mbps'
                )
            if ping_rise >= 0.25 and recent_ping is not None and base_ping is not None:
                parts.append(
                    f'زمن الاستجابة تضاعف تقريبًا ({base_ping:.0f}→{recent_ping:.0f} ms)'
                    if ping_rise >= 0.9
                    else f'زمن الاستجابة ارتفع ({base_ping:.0f}→{recent_ping:.0f} ms)'
                )
            if not parts:
                parts.append(
                    'مراقبة حيّة للخلية من القياسات'
                    if level == 'info'
                    else 'نمط غير معتاد في القياسات خلال الساعات الأخيرة'
                )
            message = (
                f'خلية {cell_id(y, x)}: '
                + ' و'.join(parts)
                + (
                    ' — احتمال عطل في البرج/القطاع القريب'
                    if level != 'info'
                    else ' — ضمن المراقبة'
                )
            )
            cell_payload = {
                'id': cell_id(y, x),
                'bounds': b,
                'lat': lat,
                'lon': lon,
                'label': f'خلية {y},{x}',
                'risk': round(risk, 3),
                'level': level,
                'priority': priority,
                'message': message,
                'factors': {
                    'complaint_ratio': round(complaint_ratio, 2),
                    'complaints_recent': round(complaints_recent, 2),
                    'complaints_expected': round(expected, 2),
                    'degradation': round(degradation, 3),
                    'speed_drop': round(speed_drop, 3),
                    'ping_rise': round(ping_rise, 3),
                    'recent_samples': len(recent),
                    'baseline_samples': len(baseline),
                    'avg_download_mbps': round(recent_dl, 2) if recent_dl is not None else None,
                    'baseline_download_mbps': round(base_dl, 2) if base_dl is not None else None,
                    'avg_ping_ms': round(recent_ping, 1) if recent_ping is not None else None,
                    'baseline_ping_ms': round(base_ping, 1) if base_ping is not None else None,
                },
            }
            viz_cells.append(cell_payload)
            if risk < 0.28 and priority < 1.2 and complaints_recent < 0.8:
                continue
            alerts.append(cell_payload)

        # Cells with complaints but no recent measurements still surface.
        for (y, x), comps in by_cell_c.items():
            if (y, x) in by_cell_m:
                continue
            recent_c = [c for c in comps if c['created_at'] >= recent_start]
            if not recent_c:
                continue
            n = sum(max(1, int(c['severity'] or 1)) for c in recent_c)
            risk = _clamp(0.4 + min(0.5, n / 6))
            b = cell_bounds(y, x)
            cell_payload = {
                'id': cell_id(y, x),
                'bounds': b,
                'lat': (b[1] + b[3]) / 2,
                'lon': (b[0] + b[2]) / 2,
                'label': f'خلية {y},{x}',
                'risk': round(risk, 3),
                'level': 'high' if risk >= 0.55 else 'watch',
                'priority': round(n * 2.2, 3),
                'message': (
                    f'خلية {cell_id(y, x)}: {n} شكوى خلال {int(recent_h)} ساعات '
                    'بدون قياسات كافية — راجع البرج القريب'
                ),
                'factors': {
                    'complaint_ratio': round(n / 0.5, 2),
                    'complaints_recent': float(n),
                    'complaints_expected': 0.5,
                    'degradation': 0.0,
                    'speed_drop': 0.0,
                    'ping_rise': 0.0,
                    'recent_samples': 0,
                    'baseline_samples': 0,
                    'avg_download_mbps': None,
                    'baseline_download_mbps': None,
                    'avg_ping_ms': None,
                    'baseline_ping_ms': None,
                },
            }
            viz_cells.append(cell_payload)
            alerts.append(cell_payload)

        alerts.sort(key=lambda a: (-a['priority'], -a['risk']))
        viz_cells.sort(key=lambda a: (-a['risk'], -a['priority']))

        # 24h city timeline of degradation / complaint pressure.
        timeline = []
        for i in range(23, -1, -1):
            t0 = now - (i + 1) * 3600
            t1 = now - i * 3600
            hour_ms = [
                r for r in measurements if t0 <= r['measurement_time'] < t1
            ]
            hour_cp = [c for c in complaints if t0 <= c['created_at'] < t1]
            soft = sum(_soft_complaint_weight(r) for r in hour_ms)
            expl = sum(max(1, int(c['severity'] or 1)) * 0.85 for c in hour_cp)
            avg_dl = _avg([float(r['download_mbps']) for r in hour_ms])
            avg_ping = _avg([float(r['ping_ms']) for r in hour_ms])
            poor_share = 0.0
            if hour_ms:
                poor_share = sum(
                    1
                    for r in hour_ms
                    if classify(float(r['download_mbps']), 'download')
                    in ('poor', 'very_poor')
                    or classify(float(r['ping_ms']), 'ping') in ('poor', 'very_poor')
                ) / len(hour_ms)
            pressure = _clamp(
                0.45 * min(1.0, (soft + expl) / 4.0) + 0.55 * poor_share
            )
            timeline.append(
                {
                    'hour_start': t0,
                    'label': datetime.fromtimestamp(t1, tz=timezone.utc).strftime('%H:00'),
                    'samples': len(hour_ms),
                    'complaints': round(soft + expl, 2),
                    'avg_download_mbps': round(avg_dl, 2) if avg_dl is not None else None,
                    'avg_ping_ms': round(avg_ping, 1) if avg_ping is not None else None,
                    'risk_index': round(pressure, 3),
                }
            )

        active = [a for a in alerts if a['level'] in ('critical', 'high', 'watch')]
        return {
            'generated_at': now,
            'window_hours': recent_h,
            'baseline_days': baseline_days,
            'alert_count': len(active),
            'alerts': alerts[:40],
            'viz_cells': viz_cells[:120],
            'priority_queue': [
                {
                    'id': a['id'],
                    'label': a['label'],
                    'level': a['level'],
                    'risk': a['risk'],
                    'priority': a['priority'],
                    'message': a['message'],
                    'bounds': a['bounds'],
                }
                for a in (active[:15] or viz_cells[:8])
            ],
            'timeline_24h': timeline,
            'summary': {
                'critical': sum(1 for a in alerts if a['level'] == 'critical'),
                'high': sum(1 for a in alerts if a['level'] == 'high'),
                'watch': sum(1 for a in alerts if a['level'] == 'watch'),
                'info': sum(1 for a in alerts if a['level'] == 'info'),
            },
        }

    @app.get('/api/outage-radar')
    def outage_radar():
        bbox = None
        raw = request.args.get('bbox')
        if raw:
            try:
                bbox = [float(x) for x in raw.split(',')]
                if len(bbox) != 4 or not (
                    -180 <= bbox[0] < bbox[2] <= 180 and -90 <= bbox[1] < bbox[3] <= 90
                ):
                    raise ValueError()
            except (ValueError, TypeError):
                raise _ApiError(422, 'الفترة أو الحدود أو الفلاتر غير صالحة')
        return jsonify(build_outage_radar(bbox))

    @app.post('/api/complaints')
    def create_complaint():
        user = current_user()
        body = request.get_json(silent=True) or {}
        category = (body.get('category') or 'outage').strip()[:40]
        if category not in ('outage', 'slow', 'no_signal', 'call_drop', 'other'):
            raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        try:
            severity = int(body.get('severity', 2))
        except (TypeError, ValueError):
            raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        if not 1 <= severity <= 5:
            raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        note = (body.get('note') or '').strip()[:280] or None
        y = x = None
        if body.get('latitude') is not None and body.get('longitude') is not None:
            try:
                lat = float(body['latitude'])
                lon = float(body['longitude'])
            except (TypeError, ValueError):
                raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
            y, x = cell_for(lat, lon)
        elif body.get('cell_id'):
            cid = str(body['cell_id'])
            parts = cid.split('_')
            if len(parts) == 3 and parts[0] == 'g1':
                try:
                    y, x = int(parts[1]), int(parts[2])
                except ValueError:
                    raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
            else:
                raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        cid = secrets.token_urlsafe(14)
        now = time.time()
        with database.connect() as db:
            # Rate-limit: one complaint per user/cell/hour.
            if y is not None:
                hour_bucket = int(now // 3600)
                dup = db.execute(
                    '''SELECT id FROM service_complaints
                       WHERE user_id=? AND cell_y=? AND cell_x=?
                         AND created_at >= ? LIMIT 1''',
                    (user['id'], y, x, hour_bucket * 3600),
                ).fetchone()
                if dup:
                    raise _ApiError(429, 'تم تسجيل نتيجة لهذه الخلية خلال الساعة؛ لا تُكرر المساهمات')
            db.execute(
                '''INSERT INTO service_complaints
                   (id,user_id,cell_y,cell_x,category,severity,note,created_at)
                   VALUES(?,?,?,?,?,?,?,?)''',
                (cid, user['id'], y, x, category, severity, note, now),
            )
        return jsonify(
            {
                'id': cid,
                'cell_id': cell_id(y, x) if y is not None else None,
                'created_at': now,
            }
        ), 201

    def load_twin_base():
        now = time.time()
        start = now - QUALITY['retention_days'] * 86400
        with database.connect() as db:
            rows = db.execute(
                'SELECT cell_y,cell_x,download_mbps,ping_ms,measurement_time '
                'FROM network_measurements WHERE cell_y IS NOT NULL AND measurement_time>=?',
                (start,),
            ).fetchall()
        measured = cells_from_measurements(rows)
        cells = ensure_grid_cells(measured, step_factor=3)
        towers = build_planning_towers(measured)
        enriched = enrich_cells(cells, towers)
        return {
            'generated_at': now,
            'note': 'نموذج تخطيطي (توأم رقمي) مبني على حدود حائل والقياسات الحية — ليس جرد أبراج رسمي.',
            'bounds': QUALITY['bounds'],
            'towers': towers,
            'cells': enriched,
            'measured_cells': len(measured),
            'avg_health': round(
                sum(c['health'] for c in enriched) / max(len(enriched), 1), 3
            ),
        }

    @app.get('/api/digital-twin')
    def digital_twin_state():
        user = current_user(required=False)
        if not user or not user.get('is_admin'):
            # Allow logged-in planners; require admin for full twin.
            if not user:
                raise _ApiError(401, 'يلزم تسجيل الدخول')
            raise _ApiError(403, 'التوأم الرقمي متاح للمدير / التخطيط')
        return jsonify(load_twin_base())

    def _twin_cells_payload(base_cells):
        return [
            {
                'id': c['id'],
                'bounds': c['bounds'],
                'lat': c['lat'],
                'lon': c['lon'],
                'sector': c['sector'],
                'sample_count': c.get('sample_count') or 0,
                'avg_download_mbps': c.get('avg_download_mbps'),
                'avg_ping_ms': c.get('avg_ping_ms'),
                'quality': c.get('quality') or {},
                'observed_base': c.get('observed_base', 0.42),
                'synthetic': c.get('synthetic', False),
            }
            for c in base_cells
        ]

    def _pack_twin_result(base, result, *, scenario: str):
        before_by_id = {c['id']: c for c in base['cells']}
        viz_cells = []
        for c in result['cells_after']:
            prev = before_by_id.get(c['id']) or {}
            delta = round(float(c['health']) - float(prev.get('health') or c['health']), 3)
            if c.get('synthetic') and abs(delta) < 0.04 and (c.get('sample_count') or 0) == 0:
                continue
            viz_cells.append(
                {
                    'id': c['id'],
                    'bounds': c['bounds'],
                    'sector': c['sector'],
                    'lat': c['lat'],
                    'lon': c['lon'],
                    'health_before': prev.get('health'),
                    'health_after': c['health'],
                    'health_label': c['health_label'],
                    'delta': delta,
                    'primary_tower': c.get('primary_tower'),
                    'sample_count': c.get('sample_count') or 0,
                }
            )
        return {
            'scenario': scenario,
            'generated_at': time.time(),
            'baseline_avg_health': base['avg_health'],
            **{k: result[k] for k in result if k != 'cells_after'},
            'viz_cells': viz_cells[:320],
            'cells_after_sample': viz_cells[:80],
        }

    def _parse_sandbox_towers(raw_towers):
        if not isinstance(raw_towers, list) or not raw_towers:
            raise _ApiError(422, 'أرسل قائمة أبراج للمحاكاة الحية')
        west, south, east, north = QUALITY['bounds']
        towers = []
        for item in raw_towers[:40]:
            if not isinstance(item, dict):
                continue
            try:
                lat = float(item.get('lat'))
                lon = float(item.get('lon'))
            except (TypeError, ValueError):
                continue
            if not (south - 0.08 <= lat <= north + 0.08 and west - 0.08 <= lon <= east + 0.08):
                continue
            towers.append(
                {
                    'id': str(item.get('id') or f'NEW-{len(towers)+1}')[:40],
                    'name': str(item.get('name') or 'برج')[:60],
                    'lat': lat,
                    'lon': lon,
                    'capacity': item.get('capacity', 1.0),
                    'radius_km': item.get('radius_km', 6.5),
                    'kind': item.get('kind') or 'proposed',
                    'active': bool(item.get('active', True)),
                }
            )
        if not towers:
            raise _ApiError(422, 'لا توجد أبراج صالحة داخل نطاق حائل')
        return towers

    @app.post('/api/digital-twin/simulate')
    def digital_twin_simulate():
        user = current_user()
        if not user.get('is_admin'):
            raise _ApiError(403, 'التوأم الرقمي متاح للمدير / التخطيط')
        body = request.get_json(silent=True) or {}
        scenario = (body.get('scenario') or 'outage').strip()
        if scenario not in ('outage', 'add', 'combo', 'sandbox'):
            raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        base = load_twin_base()
        cells = _twin_cells_payload(base['cells'])

        if scenario == 'sandbox':
            working = _parse_sandbox_towers(body.get('towers'))
            result = compare_tower_sets(cells, base['towers'], working)
            return jsonify(_pack_twin_result(base, result, scenario='sandbox'))

        disable_ids = body.get('disable_tower_ids') or []
        remove_ids = body.get('remove_tower_ids') or []
        if isinstance(disable_ids, str):
            disable_ids = [disable_ids]
        if isinstance(remove_ids, str):
            remove_ids = [remove_ids]
        if not isinstance(disable_ids, list) or not isinstance(remove_ids, list):
            raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        disable_ids = [str(x) for x in disable_ids][:12]
        remove_ids = [str(x) for x in remove_ids][:12]
        add_tower = None
        if scenario in ('add', 'combo'):
            add = body.get('add_tower') or {}
            try:
                lat = float(add.get('lat'))
                lon = float(add.get('lon'))
            except (TypeError, ValueError):
                raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
            west, south, east, north = QUALITY['bounds']
            if not (south - 0.05 <= lat <= north + 0.05 and west - 0.05 <= lon <= east + 0.05):
                raise _ApiError(422, 'الإحداثيات خارج نطاق حائل للتخطيط')
            add_tower = {
                'id': 'NEW-1',
                'name': (add.get('name') or 'برج مقترح').strip()[:60] or 'برج مقترح',
                'lat': lat,
                'lon': lon,
                'capacity': float(add.get('capacity') or 1.25),
                'radius_km': float(add.get('radius_km') or 7.0),
            }
        if scenario == 'outage' and not disable_ids and not remove_ids:
            raise _ApiError(422, 'اختر برجًا لتعطيله في السيناريو')
        if scenario == 'outage':
            add_tower = None
        if scenario == 'add':
            disable_ids = []
            remove_ids = []
        result = simulate_scenario(
            cells,
            base['towers'],
            disable_ids=disable_ids,
            remove_ids=remove_ids,
            add_tower=add_tower,
        )
        return jsonify(_pack_twin_result(base, result, scenario=scenario))

    def diagnose_my_network(lat: float, lon: float, user=None):
        y, x = cell_for(lat, lon)
        cid = cell_id(y, x)
        bounds = cell_bounds(y, x)
        radar = build_outage_radar(
            [bounds[0] - 0.02, bounds[1] - 0.02, bounds[2] + 0.02, bounds[3] + 0.02]
        )
        alert = next((a for a in radar.get('alerts') or [] if a['id'] == cid), None)
        if not alert:
            # Nearest alert within ~3 cells
            alert = next(
                (
                    a
                    for a in radar.get('alerts') or []
                    if a.get('level') in ('critical', 'high', 'watch')
                ),
                None,
            )
            if alert:
                ab = alert['bounds']
                acy, acx = (ab[1] + ab[3]) / 2, (ab[0] + ab[2]) / 2
                # Rough degree distance
                if abs(acy - lat) > 0.03 or abs(acx - lon) > 0.03:
                    alert = None

        now = time.time()
        with database.connect() as db:
            area = db.execute(
                '''SELECT AVG(download_mbps) AS dl, AVG(ping_ms) AS ping, count(*) AS n
                   FROM network_measurements
                   WHERE cell_y=? AND cell_x=? AND measurement_time>=?''',
                (y, x, now - 7 * 86400),
            ).fetchone()
            city = db.execute(
                '''SELECT AVG(download_mbps) AS dl, AVG(ping_ms) AS ping, count(*) AS n
                   FROM network_measurements WHERE measurement_time>=?''',
                (now - 7 * 86400,),
            ).fetchone()
            mine = None
            subscribed = False
            if user:
                mine = db.execute(
                    '''SELECT download_mbps,upload_mbps,ping_ms,measurement_time,cell_y,cell_x
                       FROM network_measurements WHERE user_id=?
                       ORDER BY measurement_time DESC LIMIT 1''',
                    (user['id'],),
                ).fetchone()
                sub = db.execute(
                    '''SELECT id FROM alert_subscriptions
                       WHERE user_id=? AND cell_y=? AND cell_x=? AND active=1 LIMIT 1''',
                    (user['id'], y, x),
                ).fetchone()
                subscribed = bool(sub)

        area_n = int(area['n'] or 0)
        area_dl = float(area['dl']) if area['dl'] is not None else None
        area_ping = float(area['ping']) if area['ping'] is not None else None
        city_dl = float(city['dl']) if city['dl'] is not None else None
        city_ping = float(city['ping']) if city['ping'] is not None else None

        network_bad = False
        if alert and alert.get('level') in ('critical', 'high', 'watch'):
            network_bad = True
        if area_n >= 2 and area_dl is not None and classify(area_dl, 'download') in (
            'poor',
            'very_poor',
        ):
            network_bad = True
        if area_n >= 2 and area_ping is not None and classify(area_ping, 'ping') in (
            'poor',
            'very_poor',
        ):
            network_bad = True

        device_likely = False
        if mine and not network_bad:
            mdl, mping = float(mine['download_mbps']), float(mine['ping_ms'])
            ref_dl = area_dl if area_dl is not None else city_dl
            ref_ping = area_ping if area_ping is not None else city_ping
            if ref_dl and mdl < ref_dl * 0.45 and classify(mdl, 'download') in (
                'poor',
                'very_poor',
                'moderate',
            ):
                device_likely = True
            if ref_ping and mping > ref_ping * 1.8 and mping > 100:
                device_likely = True

        if network_bad:
            verdict = 'network_issue'
            headline = 'يبدو أن المشكلة من الشبكة في منطقتك'
            detail = (
                alert['message']
                if alert
                else 'قياسات الحي أقل من المستوى المعتاد خلال الأيام الأخيرة.'
            )
            work_status = {
                'critical': 'فريق الصيانة بصدد معالجة عطل حرج',
                'high': 'تم رصد تدهور — الأولوية مرتفعة للفنيين',
                'watch': 'المنطقة تحت المراقبة الاستباقية',
            }.get((alert or {}).get('level') or 'watch', 'المنطقة تحت المراقبة')
        elif device_likely:
            verdict = 'device_likely'
            headline = 'الشبكة في الحي تبدو طبيعية — المشكلة غالبًا من الجهاز أو الواي فاي'
            detail = 'قياسات المنطقة أفضل من نتيجتك الأخيرة، لذا ننصح بخطوات التشخيص المحلية.'
            work_status = None
        elif area_n == 0 and not alert:
            verdict = 'unclear'
            headline = 'لا توجد قياسات كافية في حيّك بعد'
            detail = 'نفّذ فحص سرعة مع مشاركة الموقع لنقارن حيّك ببقية حائل.'
            work_status = None
        else:
            verdict = 'healthy'
            headline = 'الشبكة في منطقتك تبدو طبيعية'
            detail = 'لا يوجد إنذار رادار قريب. إن استمرت المشكلة عندك فجرّب خطوات التشخيص.'
            work_status = None

        diagnostics = [
            'أعد تشغيل الراوتر وانتظر دقيقتين ثم أعد الفحص.',
            'جرّب شبكة الجوال (بيانات) بدل الواي فاي للمقارنة.',
            'اقترب من الراوتر أو أزل حالة توفير الطاقة عن الواي فاي.',
            'أغلق التطبيقات الثقيلة للتحديث/البث ثم أعد فحص السرعة.',
            'إذا بقي الضعف على الجوال والواي فاي معًا، بلّغ رادار الأعطال من صفحة الفحص.',
        ]
        if verdict == 'network_issue':
            diagnostics = [
                'المشكلة مرصودة على مستوى الحي — لا حاجة لتكرار نفس الشكوى فورًا.',
                'اشترك بتنبيه هذه الخلية لتصلك تحديثات الحالة.',
                'يمكنك متابعة رادار الأعطال على الخريطة لمعرفة الأولوية.',
            ]

        return {
            'generated_at': now,
            'location': {
                'lat': lat,
                'lon': lon,
                'cell_id': cid,
                'bounds': bounds,
                'sector': sector_label(lat, lon),
            },
            'verdict': verdict,
            'headline': headline,
            'detail': detail,
            'work_status': work_status,
            'alert': alert,
            'area': {
                'samples_7d': area_n,
                'avg_download_mbps': round(area_dl, 2) if area_dl is not None else None,
                'avg_ping_ms': round(area_ping, 1) if area_ping is not None else None,
            },
            'city': {
                'samples_7d': int(city['n'] or 0),
                'avg_download_mbps': round(city_dl, 2) if city_dl is not None else None,
                'avg_ping_ms': round(city_ping, 1) if city_ping is not None else None,
            },
            'my_last_test': (
                {
                    'download_mbps': round(float(mine['download_mbps']), 2),
                    'upload_mbps': round(float(mine['upload_mbps']), 2),
                    'ping_ms': round(float(mine['ping_ms']), 1),
                    'measurement_time': mine['measurement_time'],
                    'cell_id': cell_id(mine['cell_y'], mine['cell_x'])
                    if mine['cell_y'] is not None
                    else None,
                }
                if mine
                else None
            ),
            'diagnostics': diagnostics,
            'subscribed': subscribed,
            'can_subscribe': bool(user),
        }

    @app.get('/api/my-network-status')
    def my_network_status():
        user = current_user(required=False)
        lat = lon = None
        if request.args.get('lat') is not None and request.args.get('lon') is not None:
            try:
                lat = float(request.args.get('lat'))
                lon = float(request.args.get('lon'))
            except (TypeError, ValueError):
                raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
            if not (-90 <= lat <= 90 and -180 <= lon <= 180):
                raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        elif user:
            with database.connect() as db:
                row = db.execute(
                    '''SELECT cell_y,cell_x FROM network_measurements
                       WHERE user_id=? AND cell_y IS NOT NULL
                       ORDER BY measurement_time DESC LIMIT 1''',
                    (user['id'],),
                ).fetchone()
            if row:
                b = cell_bounds(row['cell_y'], row['cell_x'])
                lat = (b[1] + b[3]) / 2
                lon = (b[0] + b[2]) / 2
        if lat is None:
            # Fallback: Hail center so the page still answers.
            west, south, east, north = QUALITY['bounds']
            lat = (south + north) / 2
            lon = (west + east) / 2
        return jsonify(diagnose_my_network(lat, lon, user))

    @app.post('/api/alert-subscriptions')
    def subscribe_alert():
        user = current_user()
        body = request.get_json(silent=True) or {}
        y = x = None
        if body.get('latitude') is not None and body.get('longitude') is not None:
            try:
                lat = float(body['latitude'])
                lon = float(body['longitude'])
            except (TypeError, ValueError):
                raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
            y, x = cell_for(lat, lon)
        elif body.get('cell_id'):
            parts = str(body['cell_id']).split('_')
            if len(parts) == 3 and parts[0] == 'g1':
                try:
                    y, x = int(parts[1]), int(parts[2])
                except ValueError:
                    raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        if y is None:
            raise _ApiError(422, 'حدد الموقع أو الخلية للاشتراك')
        sid = secrets.token_urlsafe(14)
        now = time.time()
        with database.connect() as db:
            db.execute(
                '''INSERT INTO alert_subscriptions(id,user_id,cell_y,cell_x,channel,active,created_at)
                   VALUES(?,?,?,?, 'inapp', 1, ?)
                   ON CONFLICT(user_id, cell_y, cell_x, channel) DO UPDATE SET
                     active=1, created_at=excluded.created_at''',
                (sid, user['id'], y, x, now),
            )
            row = db.execute(
                '''SELECT id FROM alert_subscriptions
                   WHERE user_id=? AND cell_y=? AND cell_x=? AND channel='inapp' AND active=1''',
                (user['id'], y, x),
            ).fetchone()
        return jsonify({'id': row['id'], 'cell_id': cell_id(y, x), 'active': True}), 201

    @app.delete('/api/alert-subscriptions')
    def unsubscribe_alert():
        user = current_user()
        body = request.get_json(silent=True) or {}
        cell = body.get('cell_id')
        if not cell:
            raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        parts = str(cell).split('_')
        if len(parts) != 3 or parts[0] != 'g1':
            raise _ApiError(422, 'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة')
        y, x = int(parts[1]), int(parts[2])
        with database.connect() as db:
            db.execute(
                '''UPDATE alert_subscriptions SET active=0
                   WHERE user_id=? AND cell_y=? AND cell_x=?''',
                (user['id'], y, x),
            )
        return Response(status=204)

    @app.get('/api/dashboard/summary')
    def dashboard_summary():
        """Public dashboard aggregates from real measurements only (zeros when empty)."""
        now = time.time()
        start_7d = now - 7 * 86400
        start_prev = now - 14 * 86400
        database.cleanup()
        with database.connect() as db:
            totals = db.execute(
                '''SELECT count(*) AS n,
                          AVG(download_mbps) AS avg_dl,
                          AVG(upload_mbps) AS avg_ul,
                          AVG(ping_ms) AS avg_ping
                   FROM network_measurements'''
            ).fetchone()
            week = db.execute(
                'SELECT count(*) FROM network_measurements WHERE measurement_time >= ?',
                (start_7d,),
            ).fetchone()[0]
            prev_week = db.execute(
                'SELECT count(*) FROM network_measurements WHERE measurement_time >= ? AND measurement_time < ?',
                (start_prev, start_7d),
            ).fetchone()[0]
            by_conn = db.execute(
                '''SELECT connection_type AS type, count(*) AS count
                   FROM network_measurements GROUP BY connection_type ORDER BY count DESC'''
            ).fetchall()
            by_day = db.execute(
                '''SELECT cast((measurement_time / 86400) as integer) AS day_bucket, count(*) AS count
                   FROM network_measurements
                   WHERE measurement_time >= ?
                   GROUP BY day_bucket ORDER BY day_bucket''',
                (start_7d,),
            ).fetchall()
            quality_rows = db.execute(
                'SELECT download_mbps FROM network_measurements'
            ).fetchall()

        n = int(totals['n'] or 0)
        quality_counts = {'good': 0, 'moderate': 0, 'poor': 0, 'very_poor': 0}
        for row in quality_rows:
            quality_counts[classify(float(row['download_mbps']), 'download')] += 1
        q_total = sum(quality_counts.values()) or 1
        good_pct = round(100 * quality_counts['good'] / q_total, 1) if n else 0.0
        weak_pct = round(
            100 * (quality_counts['poor'] + quality_counts['very_poor']) / q_total, 1
        ) if n else 0.0
        # Approximate "network quality" as share of good+moderate download samples.
        quality_score = round(
            100 * (quality_counts['good'] + quality_counts['moderate']) / q_total, 1
        ) if n else 0.0

        def delta_pct(current, previous):
            if previous <= 0:
                return None if current <= 0 else 100.0
            return round(100 * (current - previous) / previous, 1)

        day_map = {int(r['day_bucket']): int(r['count']) for r in by_day}
        trend = []
        for i in range(6, -1, -1):
            bucket = int((now - i * 86400) // 86400)
            trend.append(
                {
                    'day_bucket': bucket,
                    'date': datetime.fromtimestamp(
                        bucket * 86400, tz=timezone.utc
                    ).strftime('%Y-%m-%d'),
                    'count': day_map.get(bucket, 0),
                }
            )

        cells = query_map().get('cells') or []
        ready_cells = [c for c in cells if c.get('status') == 'ready']
        return jsonify(
            {
                'measurements': n,
                'measurements_7d': int(week),
                'measurements_delta_pct': delta_pct(int(week), int(prev_week)),
                'network_quality_pct': quality_score,
                'good_locations_pct': good_pct,
                'weak_locations_pct': weak_pct,
                'quality_breakdown': quality_counts,
                'by_connection': [dict(r) for r in by_conn],
                'trend_7d': trend,
                'avg_download_mbps': round(float(totals['avg_dl'] or 0), 2) if n else None,
                'avg_upload_mbps': round(float(totals['avg_ul'] or 0), 2) if n else None,
                'avg_ping_ms': round(float(totals['avg_ping'] or 0), 1) if n else None,
                'published_cells': len(cells),
                'ready_cells': len(ready_cells),
                'speed_available': available,
                'ai_available': bool(get_stored_gemini_key()),
                'generated_at': now,
                'empty': n == 0,
            }
        )

    @app.get('/api/network-tests/mine')
    def mine():
        user = current_user()
        try:
            limit = int(request.args.get('limit', 30))
            offset = int(request.args.get('offset', 0))
        except ValueError:
            raise _ApiError(422, 'حدود غير صالحة')
        if not 1 <= limit <= 100 or offset < 0:
            raise _ApiError(422, 'حدود غير صالحة')
        database.cleanup()
        with database.connect() as db:
            rows = db.execute(
                'SELECT id,download_mbps,upload_mbps,ping_ms,connection_type,measurement_time,test_status,server_id FROM network_measurements WHERE user_id=? ORDER BY measurement_time DESC LIMIT ? OFFSET ?',
                (user['id'], limit, offset),
            ).fetchall()
        return jsonify({'items': [dict(r) for r in rows], 'limit': limit, 'offset': offset})

    @app.delete('/api/network-tests/mine')
    def delete_mine():
        user = current_user()
        with database.connect() as db:
            db.execute('DELETE FROM network_measurements WHERE user_id=?', (user['id'],))
        return Response(status=204)

    @app.delete('/api/auth/account')
    def delete_account():
        user = current_user()
        with database.connect() as db:
            db.execute('DELETE FROM users WHERE id=?', (user['id'],))
        with lock:
            for key in list(sessions):
                if sessions[key]['user'] == user['id']:
                    del sessions[key]
        session.clear()
        return Response(status=204)

    @app.get('/api/admin/overview')
    def admin_overview():
        user = require_admin(current_user())
        with database.connect() as db:
            users_count = db.execute('SELECT count(*) FROM users').fetchone()[0]
            admins_count = db.execute(
                'SELECT count(*) FROM users WHERE is_admin=1'
            ).fetchone()[0]
            tests_count = db.execute(
                'SELECT count(*) FROM network_measurements'
            ).fetchone()[0]
            shared = db.execute(
                'SELECT count(*) FROM network_measurements WHERE cell_y IS NOT NULL'
            ).fetchone()[0]
            gemini = db.execute(
                "SELECT value FROM app_settings WHERE key='gemini_api_key'"
            ).fetchone()
            avgs = db.execute(
                '''SELECT AVG(download_mbps) AS avg_dl, AVG(upload_mbps) AS avg_ul, AVG(ping_ms) AS avg_ping,
                          MAX(measurement_time) AS last_test
                   FROM network_measurements'''
            ).fetchone()
            by_type = db.execute(
                '''SELECT connection_type AS type, count(*) AS count,
                          AVG(download_mbps) AS avg_download, AVG(ping_ms) AS avg_ping
                   FROM network_measurements GROUP BY connection_type ORDER BY count DESC'''
            ).fetchall()
            recent_users = db.execute(
                '''SELECT u.phone,u.name,count(m.id) AS tests
                   FROM users u LEFT JOIN network_measurements m ON m.user_id=u.id
                   GROUP BY u.id ORDER BY tests DESC, u.phone LIMIT 5'''
            ).fetchall()
        return jsonify(
            {
                'users': users_count,
                'admins': admins_count,
                'measurements': tests_count,
                'shared_measurements': shared,
                'avg_download_mbps': avgs['avg_dl'],
                'avg_upload_mbps': avgs['avg_ul'],
                'avg_ping_ms': avgs['avg_ping'],
                'last_measurement_at': avgs['last_test'],
                'by_connection': [dict(r) for r in by_type],
                'top_users': [dict(r) for r in recent_users],
                'gemini_configured': bool(gemini and gemini['value']),
                'speed_enabled': cfg.speed_enabled,
                'public_origin': cfg.public_origin or '',
                'db_path': cfg.db,
                'db_persistent': database.persistence_ok(),
                'persistence_hint': (
                    None
                    if database.persistence_ok()
                    else tr('قاعدة البيانات على تخزين مؤقت — ارفع الخدمة لخطة Starter مع قرص /var/data حتى لا تُمسح الحسابات عند كل نشر')
                ),
            }
        )

    @app.get('/api/admin/users')
    def admin_users():
        require_admin(current_user())
        with database.connect() as db:
            rows = db.execute(
                '''SELECT u.id,u.phone,u.name,u.first_name,u.second_name,u.family_name,u.gender,
                          u.is_admin,u.created_at,
                          (SELECT count(*) FROM network_measurements m WHERE m.user_id=u.id) AS tests
                   FROM users u
                   ORDER BY u.is_admin DESC, u.created_at DESC, u.phone'''
            ).fetchall()
        items = []
        for r in rows:
            item = {**dict(r), 'is_admin': bool(r['is_admin'])}
            gender = item.get('gender') or ''
            item['gender_label'] = (
                tr('ذكر') if gender == 'male' else tr('أنثى') if gender == 'female' else ''
            )
            created = item.get('created_at') or 0
            try:
                item['created_at_iso'] = (
                    datetime.fromtimestamp(float(created), tz=timezone.utc).isoformat()
                    if created
                    else None
                )
            except (TypeError, ValueError, OSError):
                item['created_at_iso'] = None
            items.append(item)
        return jsonify({'items': items, 'count': len(items)})

    @app.get('/api/admin/measurements')
    def admin_measurements():
        require_admin(current_user())
        try:
            limit = int(request.args.get('limit', 50))
            offset = int(request.args.get('offset', 0))
        except ValueError:
            raise _ApiError(422, 'حدود غير صالحة')
        if not 1 <= limit <= 200 or offset < 0:
            raise _ApiError(422, 'حدود غير صالحة')
        with database.connect() as db:
            rows = db.execute(
                '''SELECT m.id,m.user_id,u.phone,m.download_mbps,m.upload_mbps,m.ping_ms,m.connection_type,
                          m.cell_y,m.cell_x,m.measurement_time,m.test_status
                   FROM network_measurements m JOIN users u ON u.id=m.user_id
                   ORDER BY m.measurement_time DESC LIMIT ? OFFSET ?''',
                (limit, offset),
            ).fetchall()
        return jsonify({'items': [dict(r) for r in rows], 'limit': limit, 'offset': offset})

    @app.get('/api/admin/settings')
    def admin_settings_get():
        require_admin(current_user())
        with database.connect() as db:
            row = db.execute(
                "SELECT value FROM app_settings WHERE key='gemini_api_key'"
            ).fetchone()
        key = row['value'] if row else ''
        masked = (key[:4] + '…' + key[-4:]) if len(key) > 10 else (tr('مضبوط') if key else '')
        wa = whatsapp_otp_config()
        tok = wa.get('token_instance') or ''
        tok_masked = (tok[:4] + '…' + tok[-4:]) if len(tok) > 10 else (tr('مضبوط') if tok else '')
        return jsonify(
            {
                'gemini_api_key_set': bool(key),
                'gemini_api_key_masked': masked,
                'green_api': {
                    'enabled': bool(wa.get('enabled')),
                    'api_url': wa.get('api_url') or 'https://api.greenapi.com',
                    'id_instance': wa.get('id_instance') or '',
                    'token_instance_set': bool(tok),
                    'token_instance_masked': tok_masked,
                },
            }
        )

    def _json_body():
        data = request.get_json(silent=True, force=True)
        if data is None:
            raw = request.get_data(cache=True, as_text=True) or ''
            if not raw.strip():
                return {}
            try:
                import json as _json

                parsed = _json.loads(raw)
            except Exception:
                raise _ApiError(422, 'تعذر قراءة JSON في الطلب')
            if not isinstance(parsed, dict):
                raise _ApiError(422, 'تعذر قراءة JSON في الطلب')
            return parsed
        if not isinstance(data, dict):
            raise _ApiError(422, 'تعذر قراءة JSON في الطلب')
        return data

    @app.put('/api/admin/settings')
    def admin_settings_put():
        require_admin(current_user())
        body = _json_body()
        notes = []
        if 'gemini_api_key' in body:
            key = body.get('gemini_api_key', '')
            if not isinstance(key, str) or len(key) > 512:
                raise _ApiError(422, 'مفتاح Gemini غير صالح أو أطول من المسموح')
            key = key.strip()
            if key:
                set_app_setting('gemini_api_key', key)
                notes.append(tr('تم حفظ مفتاح المدير؛ يُستخدم لجميع مستخدمي الويب والتطبيق'))
            else:
                set_app_setting('gemini_api_key', default_gemini_api_key())
                notes.append(tr('أُعيد المفتاح الافتراضي للخادم'))

        if any(
            k in body
            for k in (
                'green_api_enabled',
                'green_api_url',
                'green_api_id_instance',
                'green_api_token_instance',
            )
        ):
            enabled = body.get('green_api_enabled', None)
            if enabled is not None:
                set_app_setting(
                    'green_api_enabled',
                    '1' if str(enabled).lower() in ('1', 'true', 'yes', 'on') else '0',
                )
            if 'green_api_url' in body:
                url = (body.get('green_api_url') or '').strip() or 'https://api.greenapi.com'
                if not isinstance(url, str) or len(url) > 200 or not url.startswith('http'):
                    raise _ApiError(422, 'رابط GREEN API غير صالح')
                set_app_setting('green_api_url', url.rstrip('/'))
            if 'green_api_id_instance' in body:
                iid = (body.get('green_api_id_instance') or '').strip()
                if len(iid) > 64:
                    raise _ApiError(422, 'معرّف GREEN API غير صالح')
                set_app_setting('green_api_id_instance', iid)
            if 'green_api_token_instance' in body:
                tok = body.get('green_api_token_instance', '')
                if not isinstance(tok, str) or len(tok) > 256:
                    raise _ApiError(422, 'توكن GREEN API غير صالح')
                tok = tok.strip()
                if tok:
                    set_app_setting('green_api_token_instance', tok)
            notes.append(tr('تم حفظ إعدادات GREEN API لواتساب'))

        if not notes:
            raise _ApiError(422, 'لا توجد إعدادات للحفظ')
        wa = whatsapp_otp_config()
        return jsonify(
            {
                'ok': True,
                'gemini_api_key_set': bool(get_stored_gemini_key()),
                'green_api_enabled': bool(wa.get('enabled')),
                'scope': 'server_wide',
                'note': ' • '.join(notes),
            }
        )

    def _parse_analyze_text():
        body = _json_body()
        text = body.get('text', '')
        if not isinstance(text, str):
            raise _ApiError(422, 'نص التحليل يجب أن يكون نصًا')
        text = text.strip()
        if len(text) < 3:
            raise _ApiError(422, 'اكتب وصفًا للتحليل (3 أحرف على الأقل)')
        if len(text) > 4000:
            raise _ApiError(422, 'نص التحليل طويل جدًا (الحد 4000 حرف)')
        return text

    @app.get('/api/ai/status')
    def ai_status():
        current_user()
        on = bool(get_stored_gemini_key())
        return jsonify(
            {
                'available': on,
                'reason': None
                if on
                else tr('المدير لم يحفظ مفتاح Gemini في الخادم بعد'),
            }
        )

    @app.post('/api/ai/analyze')
    def ai_analyze():
        """Any signed-in user; uses the admin-stored server key from DB."""
        current_user()
        throttle(('ai', request.remote_addr or '0'), 30 if cfg.testing else 12, 3600)
        return jsonify(run_gemini_analysis(_parse_analyze_text()))

    @app.post('/api/admin/analyze')
    def admin_analyze():
        require_admin(current_user())
        return jsonify(run_gemini_analysis(_parse_analyze_text()))

    @app.delete('/api/admin/users/<user_id>')
    def admin_delete_user(user_id):
        user = require_admin(current_user())
        if user_id == user['id']:
            raise _ApiError(400, 'لا يمكن حذف حساب المدير الحالي من هنا')
        with database.connect() as db:
            target = db.execute(
                'SELECT is_admin FROM users WHERE id=?', (user_id,)
            ).fetchone()
            if not target:
                raise _ApiError(404, 'المستخدم غير موجود')
            if target['is_admin']:
                raise _ApiError(400, 'لا يُحذف حساب مدير آخر من الواجهة')
            db.execute('DELETE FROM network_measurements WHERE user_id=?', (user_id,))
            db.execute('DELETE FROM auth_sessions WHERE user_id=?', (user_id,))
            db.execute('DELETE FROM users WHERE id=?', (user_id,))
        return Response(status=204)

    @app.delete('/api/admin/measurements/<measurement_id>')
    def admin_delete_measurement(measurement_id):
        require_admin(current_user())
        with database.connect() as db:
            row = db.execute(
                'SELECT id FROM network_measurements WHERE id=?', (measurement_id,)
            ).fetchone()
            if not row:
                raise _ApiError(404, 'القياس غير موجود')
            db.execute('DELETE FROM network_measurements WHERE id=?', (measurement_id,))
        return Response(status=204)

    # ─── Web pages ──────────────────────────────────────────────

    @app.context_processor
    def inject_globals():
        user = None
        try:
            user = current_user(required=False)
        except _ApiError:
            user = None
        lang = current_lang()
        other = 'en' if lang == 'ar' else 'ar'
        args = request.args.to_dict(flat=False)
        args.pop('lang', None)
        here = request.path + ('?' + urlencode(args, doseq=True) if args else '')
        return {
            'current_user': user,
            'is_admin': bool(user and user.get('is_admin')),
            'quality': QUALITY,
            '_': tr,
            'lang': lang,
            'text_dir': 'rtl' if lang in RTL_LANGS else 'ltr',
            'js_strings': js_strings(lang),
            'other_lang': other,
            'other_lang_label': LANG_LABELS[other],
            'lang_switch_url': url_for('set_lang', code=other, next=here),
            'carto_api_key': cfg.carto_api_key,
        }

    @app.get('/lang/<code>')
    def set_lang(code):
        response = redirect(safe_next(request.args.get('next'), url_for('home')))
        set_lang_cookie(response, normalize_lang(code) or DEFAULT_LANG)
        return response

    @app.get('/')
    def home():
        return render_template('home.html')

    @app.route('/login', methods=['GET', 'POST'])
    def web_login():
        error = None
        if request.method == 'POST':
            mode = request.form.get('mode', 'login')
        else:
            mode = request.args.get('mode', 'login')
        if mode not in ('login', 'register', 'reset'):
            mode = 'login'
        countries = countries_public(current_lang())
        selected_country = (request.form.get('country_code') or 'SA').strip().upper()
        if selected_country not in {c['iso'] for c in countries}:
            selected_country = 'SA'
        if request.method == 'POST':
            phone = request.form.get('phone', '').strip()
            password = request.form.get('password', '')
            try:
                if mode == 'register':
                    if whatsapp_otp_config().get('enabled'):
                        raise _ApiError(
                            422,
                            'إنشاء الحساب يتم برمز واتساب: أرسل الرمز ثم أكّده',
                        )
                    profile = parse_register(
                        {
                            'phone': phone,
                            'password': password,
                            'country_code': request.form.get('country_code', 'SA'),
                            'first_name': request.form.get('first_name', ''),
                            'second_name': request.form.get('second_name', ''),
                            'family_name': request.form.get('family_name', ''),
                            'gender': request.form.get('gender', ''),
                        }
                    )
                    try:
                        user = insert_user(profile, profile['password'])
                    except sqlite3.IntegrityError:
                        raise _ApiError(
                            409, 'هذا الرقم مسجّل مسبقًا؛ سجّل الدخول بالرقم وكلمة المرور'
                        )
                    result = issue_token(user)
                else:
                    phone, password, _iso = parse_phone_password(
                        {
                            'phone': phone,
                            'password': password,
                            'country_code': request.form.get('country_code', 'SA'),
                        }
                    )
                    with database.connect() as db:
                        row = db.execute(
                            'SELECT * FROM users WHERE phone=?', (phone,)
                        ).fetchone()
                    salt = bytes.fromhex(row['salt']) if row else bytes(16)
                    digest = hashlib.pbkdf2_hmac(
                        'sha256',
                        password.encode(),
                        salt,
                        row['hash_iterations'] if row else 600000,
                    ).hex()
                    if not row or not hmac.compare_digest(digest, row['password_hash']):
                        raise _ApiError(401, 'رقم الجوال أو كلمة المرور غير صحيحة')
                    result = issue_token(dict(row))
                session.clear()
                session.permanent = True
                session['api_token'] = result['token']
                session['user'] = result['user']
                session['expires_at'] = result['expires_at']
                return redirect(safe_next(request.args.get('next'), url_for('home')))
            except _ApiError as exc:
                error = exc.message()
        return render_template(
            'login.html',
            error=error,
            mode=mode,
            countries=countries,
            selected_country=selected_country,
            bare_layout=True,
            auth_layout=True,
        )

    @app.post('/logout')
    def web_logout():
        token = session.get('api_token')
        if token:
            with database.connect() as db:
                db.execute(
                    'DELETE FROM auth_sessions WHERE token_hash=?',
                    (hashlib.sha256(token.encode()).hexdigest(),),
                )
        session.clear()
        return redirect(url_for('home'))

    @app.get('/speed')
    def web_speed():
        return redirect(url_for('web_status') + '#speedSection')

    @app.get('/map')
    def web_map():
        return render_template(
            'map.html',
            bounds=QUALITY['bounds'],
            colors=QUALITY['colors'],
            token=(current_user(required=False) or {}).get('_token'),
        )

    @app.get('/radar')
    def web_radar():
        user = current_user(required=False)
        return render_template(
            'radar.html',
            bounds=QUALITY['bounds'],
            colors=QUALITY['colors'],
            token=(user or {}).get('_token'),
        )

    @app.get('/twin')
    def web_twin():
        user = current_user(required=False)
        if not user:
            return redirect(url_for('web_login', next=url_for('web_twin')))
        if not user.get('is_admin'):
            return render_template('admin_denied.html'), 403
        return render_template(
            'twin.html',
            bounds=QUALITY['bounds'],
            colors=QUALITY['colors'],
            token=user['_token'],
        )

    @app.get('/status')
    def web_status():
        user = current_user(required=False)
        return render_template(
            'status.html',
            bounds=QUALITY['bounds'],
            colors=QUALITY['colors'],
            token=(user or {}).get('_token'),
            logged_in=bool(user),
            speed_available=available,
            ai_available=bool(get_stored_gemini_key()),
            limits={
                'phase_max_bytes': 32 * MIB,
                'min_bytes': 4 * MIB,
                'target_seconds': 6,
                'min_phase_seconds': min_phase_seconds,
            },
        )

    @app.get('/admin')
    def web_admin():
        user = current_user(required=False)
        if not user:
            return redirect(url_for('web_login', next=url_for('web_admin')))
        if not user.get('is_admin'):
            return render_template('admin_denied.html'), 403
        return render_template('admin.html', token=user['_token'], user=user)

    @app.get('/ai')
    def web_ai():
        return redirect(url_for('web_status') + '#aiSection')

    @app.get('/help')
    def web_help():
        return render_template('help.html')

    def find_user_by_whatsapp_chat(chat_id: str):
        digits = re.sub(r'\D+', '', (chat_id or '').split('@')[0])
        if len(digits) < 8:
            return None
        candidates = [digits]
        if digits.startswith('966') and len(digits) >= 12:
            candidates.append('0' + digits[3:])
        with database.connect() as db:
            for phone in candidates:
                row = db.execute(
                    'SELECT id, phone, name, country_code FROM users WHERE phone=?',
                    (phone,),
                ).fetchone()
                if row:
                    return row
        return None

    def _wa_name(user) -> str:
        raw = (user['name'] or '').strip()
        return raw.split(' ')[0] if raw else 'عميلنا'

    def _has_any(text: str, phrases: tuple[str, ...]) -> bool:
        return any(p in text for p in phrases)

    def save_whatsapp_complaint(user, note: str) -> bool:
        """Store one WhatsApp complaint per hour. Returns False if already filed recently."""
        now = time.time()
        note = ' '.join((note or '').split())[:280]
        if len(note) < 8:
            return False
        with database.connect() as db:
            recent = db.execute(
                '''SELECT id FROM service_complaints
                   WHERE user_id=? AND created_at>=? LIMIT 1''',
                (user['id'], now - 3600),
            ).fetchone()
            if recent:
                return False
            db.execute(
                '''INSERT INTO service_complaints
                   (id,user_id,cell_y,cell_x,category,severity,note,created_at)
                   VALUES(?,?,NULL,NULL,'other',2,?,?)''',
                (secrets.token_urlsafe(14), user['id'], f'واتساب: {note}', now),
            )
        return True

    def whatsapp_reply_for_user(user, text: str) -> str | None:
        """Reply only to a clear request from a registered number. None = stay silent."""
        raw = ' '.join((text or '').split())
        if not raw or len(raw) > 400:
            return None
        q = raw.lower()
        # Ignore bare numbers, emoji-only, and very short noise.
        if re.fullmatch(r'[\d\s\W_]+', q) or len(q) < 2:
            return None
        name = _wa_name(user)

        complaint = _has_any(q, (
            'شكوى', 'شكوه', 'أشتكي', 'اشتكي', 'ابلغ', 'أبلغ', 'بلاغ',
            'اريد اقدم', 'أريد أقدم', 'ابي اقدم', 'أبغى اقدم', 'ابغى اقدم',
            'تقديم شكوى', 'قدم شكوى', 'اقدم شكوى', 'أقدم شكوى',
        ))
        inquiry = _has_any(q, (
            'استفسار', 'استفسر', 'استغسر', 'استفسر', 'سؤال', 'اسأل', 'اسال',
            'ابي اسأل', 'أبي أسأل', 'ودي اعرف', 'ودي أعرف', 'ابغى اعرف',
        ))
        password = _has_any(q, (
            'نسيت كلمة', 'نسيت الرقم السري', 'استعادة كلمة', 'نسيت الباس',
            'نسيت الباسورد', 'forgot password',
        ))
        network = _has_any(q, (
            'حالة الشبكة', 'ضعف الشبكة', 'ما فيه شبكة', 'مفيه شبكة',
            'انقطاع', 'انقطع', 'ما فيه نت', 'مافي نت', 'تغطية',
        ))
        greeting = len(q) <= 24 and _has_any(q, (
            'السلام', 'مرحبا', 'مرحبًا', 'أهلا', 'اهلا', 'هلا', 'hello', 'hi',
        ))

        if complaint:
            detail = re.sub(
                r'(اريد|أريد|ابي|أبغى|ابغى|اقدم|أقدم|تقديم|شكوى|شكوه|بلاغ)',
                ' ',
                raw,
            )
            detail = ' '.join(detail.split())
            if len(detail) >= 12:
                saved = save_whatsapp_complaint(user, raw)
                if saved:
                    return (
                        f'شكرًا {name}. تم تسجيل شكواك لدينا، وسنراجعها مع بلاغات المنطقة.\n'
                        'إذا رغبت بتفاصيل أدق، اذكر الحي ونوع المشكلة: انقطاع، بطء، أو ضعف إشارة.'
                    )
                return (
                    f'{name}، شكواك السابقة ما زالت قيد المراجعة خلال هذه الساعة. '
                    'لا حاجة لتكرارها الآن. إذا تغيّر الوضع، أعد الإرسال بعد ساعة مع وصف قصير.'
                )
            return (
                f'أهلًا {name}. نعم، نقدر نسجّل شكواك.\n'
                'اكتب رسالة تبدأ بكلمة «شكوى» ثم الحي وما الذي يحدث، مثال:\n'
                'شكوى حي النقرة: الإنترنت ينقطع منذ ساعة.'
            )

        if password:
            return (
                f'أهلًا {name}. لاستعادة كلمة المرور افتح صفحة الدخول واختر «نسيت كلمة المرور». '
                'سيصلك رمز واتساب على هذا الرقم لأن حسابك مسجّل. لا نرسل كلمة المرور هنا.'
            )

        if network:
            return (
                f'أهلًا {name}. لمتابعة التغطية سجّل الدخول ثم افتح «حالة شبكتي» أو الخريطة.\n'
                'إذا كانت المشكلة مستمرة وتود تقديم شكوى، اكتب: شكوى ثم اسم الحي ووصفًا قصيرًا.'
            )

        if inquiry:
            return (
                f'تفضل {name}، أسمعك.\n'
                'أقدر أساعدك في ثلاثة أمور فقط:\n'
                '1) حالة الشبكة بعد تسجيل الدخول\n'
                '2) تقديم شكوى: اكتب «شكوى» ثم الحي والوصف\n'
                '3) نسيان كلمة المرور من صفحة الدخول\n'
                'ما استفسارك بالتحديد؟'
            )

        if greeting:
            return (
                f'أهلًا {name}، حسابك مسجّل في SmartCare.\n'
                'هل تود تقديم شكوى، أم لديك استفسار؟\n'
                'للشكوى اكتب: شكوى ثم الحي ووصف المشكلة.\n'
                'للاستفسار اكتب سؤالك عن الشبكة أو كلمة المرور.'
            )

        return None

    def handle_whatsapp_incoming(chat_id: str, text: str):
        user = find_user_by_whatsapp_chat(chat_id)
        if not user:
            return
        cfg_wa = whatsapp_otp_config()
        if not cfg_wa.get('enabled'):
            return
        reply = whatsapp_reply_for_user(user, text)
        if not reply:
            return
        send_whatsapp_text(
            api_url=cfg_wa['api_url'],
            id_instance=cfg_wa['id_instance'],
            token_instance=cfg_wa['token_instance'],
            phone=user['phone'],
            country_iso=user['country_code'] or 'SA',
            message=reply,
        )

    def whatsapp_inbox_loop():
        while True:
            try:
                cfg_wa = whatsapp_otp_config()
                if not cfg_wa.get('enabled'):
                    time.sleep(15)
                    continue
                note = receive_notification(
                    api_url=cfg_wa['api_url'],
                    id_instance=cfg_wa['id_instance'],
                    token_instance=cfg_wa['token_instance'],
                    timeout=20,
                )
                if not note:
                    continue
                receipt = note.get('receiptId')
                parsed = incoming_text(note)
                if parsed:
                    chat_id, text = parsed
                    try:
                        handle_whatsapp_incoming(chat_id, text)
                    except Exception as exc:
                        print(f'[smartcare] whatsapp reply skipped: {exc}', flush=True)
                if receipt is not None:
                    delete_notification(
                        api_url=cfg_wa['api_url'],
                        id_instance=cfg_wa['id_instance'],
                        token_instance=cfg_wa['token_instance'],
                        receipt_id=receipt,
                    )
            except Exception as exc:
                print(f'[smartcare] whatsapp inbox: {exc}', flush=True)
                time.sleep(8)

    if not cfg.testing and os.getenv('WERKZEUG_RUN_MAIN') != 'false':
        threading.Thread(
            target=whatsapp_inbox_loop, name='wa-inbox', daemon=True
        ).start()

    return app


app = create_app()
