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
from urllib.parse import urlsplit

# Stay signed in until explicit logout (browser cookie max ~400 days).
SESSION_TTL_SECONDS = int(os.getenv('SMARTCARE_SESSION_TTL_SECONDS', str(365 * 24 * 60 * 60)))

import httpx
from flask import (
    Flask,
    Response,
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
    load_settings,
)

PHONE_RE = re.compile(r'^05\d{8}$')
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
    app.config['SESSION_COOKIE_SECURE'] = not cfg.testing
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

    stop_retention = threading.Event()

    def retention_loop():
        while not stop_retention.wait(6 * 3600):
            try:
                database.cleanup()
            except sqlite3.Error:
                pass

    threading.Thread(target=retention_loop, name='retention', daemon=True).start()

    def api_error(status: int, detail: str):
        return jsonify({'detail': detail}), status

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
        def __init__(self, status, detail):
            self.status = status
            self.detail = detail

    @app.errorhandler(_ApiError)
    def handle_api_error(err: _ApiError):
        return api_error(err.status, err.detail)

    @app.errorhandler(HTTPException)
    def handle_http(err: HTTPException):
        if request.path.startswith('/api/'):
            return api_error(err.code or 500, err.description or 'خطأ')
        return err

    @app.before_request
    def guard():
        origin = request.headers.get('origin')
        if origin and origin not in cfg.cors_origins and request.path.startswith('/api/'):
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
        return response

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
                '''SELECT u.id,u.name,u.phone,u.is_admin,u.first_name,u.second_name,u.family_name,u.gender
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
        return {
            'token': token,
            'user': public_user(user),
            'expires_in': SESSION_TTL_SECONDS,
            'expires_at': expires,
            'phone_verified': False,
        }

    def parse_phone_password(body, allowed_extra=frozenset()):
        if not isinstance(body, dict):
            raise _ApiError(422, 'حقول غير صالحة؛ أدخل رقم الجوال وكلمة المرور')
        phone = body.get('phone', '')
        password = body.get('password', '')
        if not isinstance(phone, str) or not PHONE_RE.match(phone):
            raise _ApiError(422, 'رقم الجوال يجب أن يكون 05xxxxxxxx')
        if not isinstance(password, str) or not (6 <= len(password) <= 128):
            raise _ApiError(422, 'كلمة المرور من 6 إلى 128 حرفًا')
        extra = set(body) - ({'phone', 'password'} | set(allowed_extra))
        if extra:
            raise _ApiError(422, 'حقول غير صالحة في الطلب')
        return phone, password

    def parse_name_part(value, label):
        if not isinstance(value, str):
            raise _ApiError(422, f'{label} غير صالح')
        part = ' '.join(value.split())
        if not NAME_PART_RE.match(part):
            raise _ApiError(422, f'أدخل {label} بحروف عربية أو إنجليزية (حتى 40 حرفًا)')
        return part

    def parse_register(body):
        phone, password = parse_phone_password(
            body,
            allowed_extra=frozenset(
                {'first_name', 'second_name', 'family_name', 'gender', 'name'}
            ),
        )
        first = parse_name_part(body.get('first_name', ''), 'الاسم الأول')
        second = parse_name_part(body.get('second_name', ''), 'الاسم الثاني')
        family = parse_name_part(body.get('family_name', ''), 'اسم العائلة')
        gender = body.get('gender', '')
        if not isinstance(gender, str) or gender not in GENDER_VALUES:
            raise _ApiError(422, 'اختر الجنس: ذكر أو أنثى')
        full_name = f'{first} {second} {family}'.strip()
        if len(full_name) > 120:
            raise _ApiError(422, 'الاسم الكامل طويل جدًا')
        return {
            'phone': phone,
            'password': password,
            'first_name': first,
            'second_name': second,
            'family_name': family,
            'gender': gender,
            'name': full_name,
        }

    def parse_credentials(body):
        """Legacy helper: login fields only (phone + password)."""
        phone, password = parse_phone_password(body, allowed_extra=frozenset({'name'}))
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
        return (row['value'] if row and row['value'] else '') or ''

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
                            'text': 'أنت مساعد تحليل شبكة اتصالات لحائل. أجب بالعربية باختصار ووضوح.\n\n'
                            + text
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
            detail = 'مفتاح Gemini مرفوض أو غير صالح'
            try:
                err = listed.json().get('error', {}).get('message')
                if err:
                    detail = f'رفض Gemini: {err}'
            except Exception:
                pass
            raise _ApiError(502, detail)

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
                detail = 'لا يوجد نموذج Gemini متاح لهذا المفتاح'
                try:
                    err = last_body.json().get('error', {}).get('message')
                    if err:
                        detail = f'رفض Gemini: {err}'
                except Exception:
                    pass
                raise _ApiError(502, detail)
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
                    else 'لم يُضبط خادم قياس عام عبر HTTPS؛ اختبار الإنترنت غير متاح',
                    'server_id': cfg.public_origin
                    or ('http://localhost:8765' if local_speed else 'unconfigured'),
                    'max_bytes': 64 * MIB,
                    'max_seconds': 90,
                    'phase_max_bytes': 32 * MIB,
                    'target_seconds': 6,
                    'min_phase_seconds': 0.25,
                },
                'ai': {
                    'available': gemini_on,
                    'reason': None
                    if gemini_on
                    else 'المدير لم يحفظ مفتاح Gemini في الخادم بعد',
                },
                'carrier': {
                    'available': False,
                    'reason': 'لا يوجد مصدر موثوق لتحديد شركة الاتصالات؛ لا يتم تخمينها',
                },
                'privacy': {
                    'min_contributors': QUALITY['min_contributors'],
                    'retention_days': QUALITY['retention_days'],
                    'location': 'cell_only',
                    'auth': 'password_accounts_phone_unverified',
                },
            }
        )

    def insert_user(profile, password, *, is_admin=0):
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac(
            'sha256', password.encode(), bytes.fromhex(salt), 600000
        ).hex()
        user = {
            'id': secrets.token_urlsafe(18),
            'name': profile['name'],
            'phone': profile['phone'],
            'first_name': profile.get('first_name', ''),
            'second_name': profile.get('second_name', ''),
            'family_name': profile.get('family_name', ''),
            'gender': profile.get('gender', ''),
            'is_admin': bool(is_admin),
        }
        with database.connect() as db:
            db.execute(
                '''INSERT INTO users(
                    id,phone,name,first_name,second_name,family_name,gender,
                    salt,password_hash,hash_iterations,is_admin,created_at
                   ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',
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
        phone, password = parse_phone_password(body)
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
            and 0.25 <= download_seconds <= 90
            and 0.25 <= upload_seconds <= 90
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
                    else 'قاعدة البيانات على تخزين مؤقت — ارفع الخدمة لخطة Starter مع قرص /var/data حتى لا تُمسح الحسابات عند كل نشر'
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
                'ذكر' if gender == 'male' else 'أنثى' if gender == 'female' else ''
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
        masked = (key[:4] + '…' + key[-4:]) if len(key) > 10 else ('مضبوط' if key else '')
        return jsonify({'gemini_api_key_set': bool(key), 'gemini_api_key_masked': masked})

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
        key = body.get('gemini_api_key', '')
        if not isinstance(key, str) or len(key) > 512:
            raise _ApiError(422, 'مفتاح Gemini غير صالح أو أطول من المسموح')
        key = key.strip()
        with database.connect() as db:
            if key:
                db.execute(
                    'INSERT INTO app_settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at',
                    ('gemini_api_key', key, time.time()),
                )
            else:
                db.execute("DELETE FROM app_settings WHERE key='gemini_api_key'")
        return jsonify(
            {
                'ok': True,
                'gemini_api_key_set': bool(key),
                'scope': 'server_wide',
                'note': 'المفتاح محفوظ في قاعدة البيانات ويُستخدم لجميع مستخدمي الويب والتطبيق',
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
                else 'المدير لم يحفظ مفتاح Gemini في الخادم بعد',
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
        return {
            'current_user': user,
            'is_admin': bool(user and user.get('is_admin')),
            'quality': QUALITY,
        }

    @app.get('/')
    def home():
        return render_template('home.html')

    @app.route('/login', methods=['GET', 'POST'])
    def web_login():
        error = None
        mode = request.form.get('mode', 'login') if request.method == 'POST' else 'login'
        if request.method == 'POST':
            phone = request.form.get('phone', '').strip()
            password = request.form.get('password', '')
            mode = request.form.get('mode', 'login')
            try:
                if mode == 'register':
                    profile = parse_register(
                        {
                            'phone': phone,
                            'password': password,
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
                    phone, password = parse_phone_password(
                        {'phone': phone, 'password': password}
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
                nxt = request.args.get('next') or url_for('home')
                return redirect(nxt)
            except _ApiError as exc:
                error = exc.detail
        return render_template('login.html', error=error, mode=mode)

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
        user = current_user(required=False)
        if not user:
            return redirect(url_for('web_login', next=url_for('web_speed')))
        return render_template(
            'speed.html', token=user['_token'], available=available
        )

    @app.get('/map')
    def web_map():
        return render_template(
            'map.html',
            bounds=QUALITY['bounds'],
            colors=QUALITY['colors'],
            token=(current_user(required=False) or {}).get('_token'),
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
        user = current_user(required=False)
        if not user:
            return redirect(url_for('web_login', next=url_for('web_ai')))
        return render_template(
            'ai.html',
            token=user['_token'],
            available=bool(get_stored_gemini_key()),
        )

    return app


app = create_app()
