"""SmartCare measured-network API. No synthetic production measurements.

Run: python -m uvicorn backend.app:app --host 127.0.0.1 --port 8765
Public speed service is opt-in and must sit behind HTTPS (see README).
"""
import asyncio
import hashlib
import hmac
import ipaddress
import json
import math
import os
import secrets
import socket
import sqlite3
import statistics
import threading
import time
from collections import defaultdict, deque
from contextlib import contextmanager, asynccontextmanager, suppress
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlsplit

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
import httpx
from pydantic import BaseModel, ConfigDict, Field

ROOT = Path(__file__).parent
QUALITY = json.loads((ROOT / 'quality.json').read_text(encoding='utf-8'))
MIB = 1024 * 1024

@dataclass
class Settings:
    db: str = str(ROOT / 'data' / 'smartcare.sqlite3')
    public_origin: str = ''
    speed_enabled: bool = False
    testing: bool = False
    cors_origins: tuple = ('http://localhost:8080', 'http://127.0.0.1:8080')

class Credentials(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True)
    phone: str = Field(pattern=r'^05\d{8}$')
    password: str = Field(min_length=6, max_length=128)
    name: str = Field(default='', max_length=80)

class MeasurementIn(BaseModel):
    model_config = ConfigDict(extra='forbid', strict=True, allow_inf_nan=False)
    session_id: str = Field(min_length=20, max_length=100)
    download_mbps: float = Field(gt=0, le=10000)
    upload_mbps: float = Field(gt=0, le=10000)
    ping_ms: float = Field(gt=0, le=10000)
    download_seconds: float = Field(ge=0.25, le=90)
    upload_seconds: float = Field(ge=0.25, le=90)
    download_bytes: int = Field(ge=4*MIB, le=32*MIB)
    upload_bytes: int = Field(ge=4*MIB, le=32*MIB)
    connection_type: str = Field(pattern=r'^(wifi|cellular|ethernet|unknown)$')
    connection_source: str = Field(pattern=r'^(os_interface|unavailable)$')
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    location_accuracy_m: float | None = Field(default=None, gt=0, le=10000)
    share_location: bool = False
    measurement_time: float
    test_status: str = Field(pattern=r'^completed$')

def cell_for(lat, lon):
    step = QUALITY['cell_degrees']
    return math.floor((lat + 1e-9) / step), math.floor((lon + 1e-9) / step)

def cell_id(y, x):
    return f'g1_{y}_{x}'

def cell_bounds(y, x):
    step = QUALITY['cell_degrees']
    return [round(x*step, 6), round(y*step, 6), round((x+1)*step, 6), round((y+1)*step, 6)]

def classify(value, metric):
    a, b, c = QUALITY[metric]
    if metric == 'ping':
        return 'good' if value <= a else 'moderate' if value <= b else 'poor' if value <= c else 'very_poor'
    return 'very_poor' if value < a else 'poor' if value < b else 'moderate' if value < c else 'good'

class Database:
    def __init__(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = path
        with self.connect() as db:
            db.executescript('''
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, phone TEXT UNIQUE NOT NULL, name TEXT NOT NULL, salt TEXT NOT NULL, password_hash TEXT NOT NULL, hash_iterations INTEGER NOT NULL DEFAULT 600000, is_admin INTEGER NOT NULL DEFAULT 0);
              CREATE TABLE IF NOT EXISTS auth_sessions(token_hash TEXT PRIMARY KEY, user_id TEXT REFERENCES users(id) ON DELETE CASCADE, expires REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at REAL NOT NULL);
              CREATE TABLE IF NOT EXISTS network_measurements(
                id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                download_mbps REAL NOT NULL, upload_mbps REAL NOT NULL, ping_ms REAL NOT NULL,
                jitter_ms REAL, packet_loss_percent REAL, connection_type TEXT NOT NULL, connection_source TEXT NOT NULL,
                carrier_name TEXT, carrier_source TEXT, cell_y INTEGER, cell_x INTEGER, location_accuracy_m REAL,
                measurement_time REAL NOT NULL, created_at REAL NOT NULL, test_status TEXT NOT NULL,
                server_id TEXT NOT NULL, session_id TEXT UNIQUE NOT NULL, hour_bucket INTEGER NOT NULL,
                UNIQUE(user_id,cell_y,cell_x,hour_bucket));
              CREATE INDEX IF NOT EXISTS measurement_geo_time ON network_measurements(cell_y,cell_x,measurement_time);
              CREATE INDEX IF NOT EXISTS measurement_time ON network_measurements(measurement_time);
            ''')
            cols = {r[1] for r in db.execute('PRAGMA table_info(users)')}
            if 'hash_iterations' not in cols:
                db.execute('ALTER TABLE users ADD COLUMN hash_iterations INTEGER NOT NULL DEFAULT 310000')
            if 'is_admin' not in cols:
                db.execute('ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0')
        if os.name == 'posix':
            with suppress(OSError):
                os.chmod(path,0o600)

    def seed_admin(self, phone='0552515874', password='123456', name='مدير النظام'):
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 600000).hex()
        with self.connect() as db:
            row = db.execute('SELECT id FROM users WHERE phone=?', (phone,)).fetchone()
            if row:
                db.execute(
                    'UPDATE users SET name=?, salt=?, password_hash=?, hash_iterations=600000, is_admin=1 WHERE phone=?',
                    (name, salt, digest, phone),
                )
            else:
                db.execute(
                    'INSERT INTO users(id,phone,name,salt,password_hash,hash_iterations,is_admin) VALUES(?,?,?,?,?,?,1)',
                    (secrets.token_urlsafe(18), phone, name, salt, digest, 600000),
                )
            if os.getenv('SMARTCARE_GEMINI_API_KEY'):
                db.execute(
                    'INSERT INTO app_settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at',
                    ('gemini_api_key', os.getenv('SMARTCARE_GEMINI_API_KEY'), time.time()),
                )
    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.path, timeout=15)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        try:
            yield db
            db.commit()
        except Exception:
            db.rollback()
            raise
        finally:
            db.close()
    def cleanup(self):
        with self.connect() as db:
            db.execute('DELETE FROM network_measurements WHERE measurement_time < ?', (time.time()-QUALITY['retention_days']*86400,))
            db.execute('DELETE FROM auth_sessions WHERE expires < ?', (time.time(),))

def create_app(settings=None):
    cfg = settings or Settings(db=os.getenv('SMARTCARE_DB', Settings.db), public_origin=os.getenv('SMARTCARE_PUBLIC_ORIGIN', ''), speed_enabled=os.getenv('SMARTCARE_SPEED_ENABLED') == '1', cors_origins=tuple(os.getenv('SMARTCARE_CORS', 'http://localhost:8080,http://127.0.0.1:8080').split(',')))
    database = Database(cfg.db)
    database.seed_admin(
        phone=os.getenv('SMARTCARE_ADMIN_PHONE', '0552515874'),
        password=os.getenv('SMARTCARE_ADMIN_PASSWORD', '123456'),
        name=os.getenv('SMARTCARE_ADMIN_NAME', 'مدير النظام'),
    )
    @asynccontextmanager
    async def lifespan(app):
        database.cleanup()
        async def retention_worker():
            while True:
                await asyncio.sleep(6*3600)
                try:
                    await asyncio.to_thread(database.cleanup)
                except sqlite3.Error:
                    pass # Queries also clean up; retry at the next interval.
        task=asyncio.create_task(retention_worker())
        try:
            yield
        finally:
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task
    app = FastAPI(title='SmartCare Network Quality', version='1.0.0', docs_url='/docs' if not cfg.speed_enabled else None, redoc_url=None, lifespan=lifespan)
    app.state.database = database
    app.state.test_sessions = {}
    @app.exception_handler(RequestValidationError)
    async def validation_error(request:Request, error:RequestValidationError):
        # Never echo credentials, coordinates, NaN/Infinity, or raw submissions.
        return JSONResponse(status_code=422,content={'detail':'حقول غير صالحة؛ تحقق من القياسات والإحداثيات والقيم المطلوبة'})
    sessions = app.state.test_sessions
    lock = threading.Lock()
    limits = defaultdict(deque)
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
        if url.scheme != 'https' or not url.hostname or url.username or url.password or url.path not in ('', '/'):
            return False
        try:
            addresses = socket.getaddrinfo(url.hostname, 443, type=socket.SOCK_STREAM)
            return bool(addresses) and all(ipaddress.ip_address(a[4][0]).is_global for a in addresses)
        except OSError:
            return False
    available = speed_available()
    local_speed = available and not cfg.testing and loopback_origin(cfg.public_origin)
    app.add_middleware(CORSMiddleware, allow_origins=list(cfg.cors_origins), allow_methods=['GET','POST','PUT','DELETE'], allow_headers=['Authorization','Content-Type','X-Test-Session','Cache-Control'], expose_headers=['Content-Length','Content-Encoding'], max_age=600)

    def throttle(key, count, seconds):
        now = time.monotonic()
        with lock:
            entries = limits[key]
            while entries and entries[0] < now-seconds:
                entries.popleft()
            if len(entries) >= count:
                raise HTTPException(429, 'طلبات كثيرة؛ حاول لاحقًا')
            entries.append(now)
            if len(limits) > 20000:
                for k in list(limits):
                    if not limits[k] or limits[k][-1] < now-3600:
                        del limits[k]

    @app.middleware('http')
    async def guard(request: Request, call_next):
        origin = request.headers.get('origin')
        if origin and origin not in cfg.cors_origins:
            return Response(status_code=403)
        if request.method != 'OPTIONS':
            try:
                throttle(('ip', request.client.host), 2000 if (cfg.testing or cfg.speed_enabled) else 180, 60)
            except HTTPException:
                return Response(status_code=429)
        length = request.headers.get('content-length', '0')
        try:
            max_body = 2*MIB if request.url.path == '/api/speed/upload' else 16384
            if int(length) < 0 or int(length) > max_body:
                return Response(status_code=413)
        except ValueError:
            return Response(status_code=400)
        if request.method in ('POST','PUT','DELETE') and request.url.path != '/api/speed/upload':
            # Bound chunked bodies too, before Pydantic reads them.
            raw = bytearray()
            async for chunk in request.stream():
                raw.extend(chunk)
                if len(raw) > 16384:
                    return Response(status_code=413)
            request._body = bytes(raw)
        response = await call_next(request)
        response.headers['Cache-Control'] = 'no-store, no-cache, max-age=0'
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        return response

    def current_user(request: Request):
        auth = request.headers.get('authorization', '')
        if not auth.startswith('Bearer '):
            raise HTTPException(401, 'يلزم تسجيل الدخول بالخادم')
        digest = hashlib.sha256(auth[7:].encode()).hexdigest()
        with database.connect() as db:
            row = db.execute('SELECT u.id,u.name,u.phone,u.is_admin FROM auth_sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=? AND s.expires>?', (digest,time.time())).fetchone()
        if not row:
            raise HTTPException(401, 'انتهت جلسة الدخول')
        user = dict(row)
        user['is_admin'] = bool(user.get('is_admin'))
        return user

    @app.get('/api/network-config')
    def config():
        return {'quality':QUALITY, 'test':{'available':available, 'mode':'integration_test' if cfg.testing else 'local' if local_speed else 'internet', 'reason':None if available else 'لم يُضبط خادم قياس عام عبر HTTPS؛ اختبار الإنترنت غير متاح', 'server_id':cfg.public_origin or ('http://localhost:8765' if local_speed else 'unconfigured'), 'max_bytes':64*MIB, 'max_seconds':90, 'phase_max_bytes':32*MIB, 'target_seconds':6, 'min_phase_seconds':0.25}, 'carrier':{'available':False, 'reason':'لا يوجد مصدر موثوق لتحديد شركة الاتصالات؛ لا يتم تخمينها'}, 'privacy':{'min_contributors':QUALITY['min_contributors'], 'retention_days':QUALITY['retention_days'], 'location':'cell_only', 'auth':'password_accounts_phone_unverified'}}

    def issue_token(user):
        token = secrets.token_urlsafe(32)
        with database.connect() as db:
            db.execute('INSERT INTO auth_sessions VALUES(?,?,?)', (hashlib.sha256(token.encode()).hexdigest(),user['id'],time.time()+8*3600))
        return {'token':token, 'user':{'id':user['id'],'name':user['name'],'phone':user['phone'],'is_admin':bool(user.get('is_admin'))}, 'expires_in':28800, 'phone_verified':False}

    def require_admin(user):
        if not user.get('is_admin'):
            raise HTTPException(403, 'هذه الصفحة للمدير فقط')
        return user

    class AdminSettingsIn(BaseModel):
        model_config = ConfigDict(extra='forbid', strict=True)
        gemini_api_key: str = Field(default='', max_length=200)

    class AnalyzeIn(BaseModel):
        model_config = ConfigDict(extra='forbid', strict=True)
        text: str = Field(min_length=3, max_length=4000)

    @app.post('/api/auth/register', status_code=201)
    def register(data: Credentials, request: Request):
        throttle(('auth',request.client.host), 40 if (cfg.testing or cfg.speed_enabled) else 8, 900)
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac('sha256', data.password.encode(), bytes.fromhex(salt),600000).hex()
        user = {'id':secrets.token_urlsafe(18),'name':data.name.strip() or 'مستخدم SmartCare','phone':data.phone,'is_admin':False}
        try:
            with database.connect() as db:
                db.execute('INSERT INTO users(id,phone,name,salt,password_hash,hash_iterations,is_admin) VALUES(?,?,?,?,?,?,0)',(user['id'],user['phone'],user['name'],salt,digest,600000))
        except sqlite3.IntegrityError:
            raise HTTPException(409,'تعذر إنشاء الحساب؛ جرّب تسجيل الدخول')
        return issue_token(user)

    @app.post('/api/auth/login')
    def login(data: Credentials, request: Request):
        throttle(('auth',request.client.host),40 if (cfg.testing or cfg.speed_enabled) else 8,900)
        with database.connect() as db:
            row = db.execute('SELECT * FROM users WHERE phone=?',(data.phone,)).fetchone()
        salt = bytes.fromhex(row['salt']) if row else bytes(16)
        digest = hashlib.pbkdf2_hmac('sha256',data.password.encode(),salt,row['hash_iterations'] if row else 600000).hex()
        if not row or not hmac.compare_digest(digest,row['password_hash']):
            raise HTTPException(401,'رقم الجوال أو كلمة المرور غير صحيحة')
        if row['hash_iterations']<600000:
            upgraded=hashlib.pbkdf2_hmac('sha256',data.password.encode(),salt,600000).hex()
            with database.connect() as db:
                db.execute('UPDATE users SET password_hash=?,hash_iterations=600000 WHERE id=?',(upgraded,row['id']))
        return issue_token(dict(row))

    @app.delete('/api/auth/session', status_code=204)
    def logout(request: Request, user=Depends(current_user)):
        with database.connect() as db:
            db.execute('DELETE FROM auth_sessions WHERE token_hash=?',(hashlib.sha256(request.headers['authorization'][7:].encode()).hexdigest(),))
        return Response(status_code=204)

    def get_test(request, user):
        sid = request.headers.get('x-test-session','')
        s = sessions.get(sid)
        if not s or s['user'] != user['id'] or time.monotonic()-s['started'] > 120 or s['used']:
            raise HTTPException(409,'جلسة قياس غير صالحة أو منتهية')
        return s

    @app.post('/api/speed/sessions',status_code=201)
    def start_test(user=Depends(current_user)):
        if not available:
            raise HTTPException(503,'اختبار الإنترنت غير متاح حتى إعداد خادم عام مناسب')
        throttle(('tests',user['id']),100 if (cfg.testing or cfg.speed_enabled) else 4,3600)
        with lock:
            for key in list(sessions):
                if time.monotonic()-sessions[key]['started'] > 180:
                    del sessions[key]
            sid = secrets.token_urlsafe(24)
            sessions[sid] = {'user':user['id'],'started':time.monotonic(),'download':0,'upload':0,'ping':0,'used':False}
        return {'session_id':sid,'max_bytes':64*MIB,'max_seconds':90}

    @app.get('/api/speed/ping')
    def ping(request: Request,user=Depends(current_user)):
        s=get_test(request,user)
        with lock: s['ping'] += 1
        return {'ok':True}

    download_payload = os.urandom(2*MIB)

    @app.get('/api/speed/download')
    def download(request: Request,size:int=Query(2*MIB,ge=65536,le=2*MIB),user=Depends(current_user)):
        s=get_test(request,user)
        with lock:
            if s['download']+size > 32*MIB:
                raise HTTPException(413,'انتهت ميزانية التنزيل')
            s['download'] += size
        return Response(content=download_payload[:size], media_type='application/octet-stream', headers={'Content-Length':str(size),'Content-Encoding':'identity','Cache-Control':'no-store','X-Accel-Buffering':'no'})

    @app.post('/api/speed/upload')
    async def upload(request:Request,user=Depends(current_user)):
        s=get_test(request,user)
        if request.headers.get('content-encoding') not in (None,'identity'):
            raise HTTPException(400,'لا تقبل بيانات قياس مضغوطة')
        count=0
        async def receive():
            nonlocal count
            async for chunk in request.stream():
                count += len(chunk)
                if count > 2*MIB:
                    raise HTTPException(413,'حجم رفع غير مسموح')
        try:
            await asyncio.wait_for(receive(),30)
        except asyncio.TimeoutError:
            raise HTTPException(408,'انتهى وقت الرفع')
        if count < 65536:
            raise HTTPException(422,'عينة رفع صغيرة جدًا')
        with lock:
            if s['upload']+count > 32*MIB:
                raise HTTPException(413,'انتهت ميزانية الرفع')
            s['upload'] += count
        return {'received_bytes':count}

    @app.post('/api/network-tests',status_code=201)
    def save_measurement(data:MeasurementIn,user=Depends(current_user)):
        s=sessions.get(data.session_id)
        if not available or not s or s['used'] or s['user']!=user['id'] or time.monotonic()-s['started']>180:
            raise HTTPException(409,'نتيجة بلا جلسة نقل بيانات موثقة')
        if s['download']!=data.download_bytes or s['upload']!=data.upload_bytes or s['ping']<7:
            raise HTTPException(422,'لا تتطابق النتيجة مع نقل البيانات على الخادم')
        for rate,byte_count,seconds in [(data.download_mbps,data.download_bytes,data.download_seconds),(data.upload_mbps,data.upload_bytes,data.upload_seconds)]:
            if not math.isclose(rate,byte_count*8/seconds/1_000_000,rel_tol=.03):
                raise HTTPException(422,'معدل النقل لا يطابق الحجم والمدة')
        elapsed=time.monotonic()-s['started']
        if data.download_seconds+data.upload_seconds>elapsed+1 or abs(data.measurement_time-time.time())>300:
            raise HTTPException(422,'توقيت القياس غير صالح')
        y=x=None
        if data.share_location:
            if data.latitude is None or data.longitude is None or data.location_accuracy_m is None:
                raise HTTPException(422,'مشاركة الخريطة تحتاج موافقة وموقعًا ودقة معلومين')
            west,south,east,north=QUALITY['bounds']
            if not (south<=data.latitude<=north and west<=data.longitude<=east):
                raise HTTPException(422,'الموقع خارج نطاق حائل المدعوم حاليًا')
            if data.location_accuracy_m>1000:
                raise HTTPException(422,'دقة الموقع غير كافية لتصنيف خلية؛ يمكنك الحفظ دون مشاركة')
            y,x=cell_for(data.latitude,data.longitude)
        elif data.latitude is not None or data.longitude is not None or data.location_accuracy_m is not None:
            raise HTTPException(422,'لا ترسل موقعًا دون الموافقة على المشاركة')
        if data.connection_type!='unknown' and data.connection_source!='os_interface':
            raise HTTPException(422,'نوع الاتصال يحتاج مصدر واجهة الجهاز')
        database.cleanup()
        mid=secrets.token_urlsafe(18)
        try:
            with database.connect() as db:
                db.execute('''INSERT INTO network_measurements(id,user_id,download_mbps,upload_mbps,ping_ms,connection_type,connection_source,cell_y,cell_x,location_accuracy_m,measurement_time,created_at,test_status,server_id,session_id,hour_bucket) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''', (mid,user['id'],data.download_mbps,data.upload_mbps,data.ping_ms,data.connection_type,data.connection_source,y,x,math.ceil(data.location_accuracy_m/100)*100 if y is not None else None,data.measurement_time,time.time(),data.test_status,cfg.public_origin or 'integration-test',data.session_id,int(data.measurement_time//3600)))
        except sqlite3.IntegrityError:
            raise HTTPException(409,'تم تسجيل نتيجة لهذه الخلية خلال الساعة؛ لا تُكرر المساهمات')
        with lock: s['used']=True
        return {'id':mid,'shared':y is not None,'cell_id':cell_id(y,x) if y is not None else None}

    def query_map(request:Request):
        q=request.query_params
        try:
            now=time.time()
            start=float(q.get('start',now-7*86400)); end=float(q.get('end',now))
            bbox=[float(v) for v in q.get('bbox',','.join(map(str,QUALITY['bounds']))).split(',')]
            minimum=int(q.get('min_samples',QUALITY['min_samples']))
            min_download=float(q.get('min_download',0)); max_ping=float(q.get('max_ping',10000))
            if len(bbox)!=4 or not all(math.isfinite(v) for v in bbox+[start,end,min_download,max_ping]) or not (-180<=bbox[0]<bbox[2]<=180 and -90<=bbox[1]<bbox[3]<=90):
                raise ValueError()
            if not 0<end-start<=90*86400 or end>now+60 or not 0<=min_download<=10000 or not 0<max_ping<=10000 or not QUALITY['min_samples']<=minimum<=100:
                raise ValueError()
        except (ValueError,TypeError):
            raise HTTPException(422,'الفترة أو الحدود أو الفلاتر غير صالحة')
        metric=q.get('metric','download'); connection=q.get('connection','all')
        if metric not in ('download','upload','ping','density') or connection not in ('all','wifi','cellular','ethernet','unknown') or q.get('carrier','all')!='all':
            raise HTTPException(422,'فلتر غير مدعوم؛ بيانات شركة الاتصالات غير متاحة')
        database.cleanup()
        step=QUALITY['cell_degrees']
        # Grid columns, never raw coordinates; bound both geography and time.
        sql='SELECT * FROM network_measurements WHERE cell_y IS NOT NULL AND measurement_time BETWEEN ? AND ? AND cell_x BETWEEN ? AND ? AND cell_y BETWEEN ? AND ? AND download_mbps>=? AND ping_ms<=?'
        args=[start,end,math.floor(bbox[0]/step),math.floor(bbox[2]/step),math.floor(bbox[1]/step),math.floor(bbox[3]/step),min_download,max_ping]
        if connection!='all': sql+=' AND connection_type=?'; args.append(connection)
        with database.connect() as db:
            rows=db.execute(sql+' ORDER BY measurement_time DESC LIMIT 50001',args).fetchall()
        if len(rows)>50000:
            raise HTTPException(413,'نطاق كبير؛ ضيق الفترة أو حدود العرض')
        groups=defaultdict(list)
        for row in rows: groups[(row['cell_y'],row['cell_x'])].append(row)
        output=[]
        for (y,x),items in groups.items():
            if len(set(r['user_id'] for r in items))<QUALITY['min_contributors']:
                continue # Never reveal even the existence/count of one person's cell.
            latest=max(r['measurement_time'] for r in items)
            n=len(items); sufficient=n>=minimum
            stale=now-latest>QUALITY['stale_hours']*3600
            cell={'id':cell_id(y,x),'bounds':cell_bounds(y,x),'name':None,'sample_count':n if sufficient else None,'status':'insufficient' if not sufficient else 'stale' if stale else 'ready','last_measurement':latest if sufficient else None,'age_hours':round((now-latest)/3600,1) if sufficient else None,'confidence':'adequate_sample' if sufficient and not stale else 'limited','statistics':None,'quality':None,'carrier':None}
            if sufficient:
                stats={}
                for key in ('download_mbps','upload_mbps','ping_ms'):
                    values=[r[key] for r in items]
                    stats[key]={'mean':round(statistics.mean(values),3),'median':round(statistics.median(values),3)}
                stats.update(jitter_ms=None,packet_loss_percent=None)
                cell['statistics']=stats
                cell['quality']={k:classify(stats[v]['median'],k) if not stale else 'stale' for k,v in [('download','download_mbps'),('upload','upload_mbps'),('ping','ping_ms')]}
                cell['connections']=sorted(set(r['connection_type'] for r in items))
            output.append(cell)
        return {'cells':output,'generated_at':now,'start':start,'end':end,'min_samples':minimum,'metric':metric,'quality_version':QUALITY['version'],'suppression':'Cells with fewer than three contributors are not returned; counts are hidden until sample minimum is met.'}

    @app.get('/api/network-heatmap')
    def heatmap(request:Request):
        return query_map(request)

    @app.get('/api/network-heatmap/mine')
    def heatmap_mine(user=Depends(current_user)):
        now=time.time(); start=now-QUALITY['retention_days']*86400
        with database.connect() as db:
            rows=db.execute('SELECT * FROM network_measurements WHERE user_id=? AND cell_y IS NOT NULL AND measurement_time>=? ORDER BY measurement_time DESC LIMIT 5000',(user['id'],start)).fetchall()
        groups=defaultdict(list)
        for row in rows: groups[(row['cell_y'],row['cell_x'])].append(row)
        output=[]
        for (y,x),items in groups.items():
            latest=max(r['measurement_time'] for r in items)
            stats={}
            for key in ('download_mbps','upload_mbps','ping_ms'):
                values=[r[key] for r in items]
                stats[key]={'mean':round(statistics.mean(values),3),'median':round(statistics.median(values),3)}
            output.append({'id':cell_id(y,x),'bounds':cell_bounds(y,x),'name':None,'sample_count':len(items),'status':'personal','last_measurement':latest,'age_hours':round((now-latest)/3600,1),'confidence':'owner_sample','statistics':stats,'quality':{k:classify(stats[v]['median'],k) for k,v in [('download','download_mbps'),('upload','upload_mbps'),('ping','ping_ms')]},'connections':sorted(set(r['connection_type'] for r in items)),'owner':True})
        return {'cells':output,'generated_at':now}

    @app.get('/api/network-areas/{area_id}')
    def area_details(area_id:str,request:Request):
        result=query_map(request)
        for cell in result['cells']:
            if cell['id']==area_id:
                return {'cell':cell,'start':result['start'],'end':result['end']}
        raise HTTPException(404,'لا توجد بيانات منشورة كافية لهذه الخلية')

    @app.get('/api/network-statistics')
    def statistics_api(request:Request):
        data=query_map(request)
        ready=[c for c in data['cells'] if c['status']=='ready']
        return {'published_cells':len(data['cells']),'ready_cells':len(ready),'sample_count':sum(c['sample_count'] or 0 for c in data['cells']),'generated_at':data['generated_at'],'note':'Statistics use privacy-filtered cells only; unweighted cell medians are not presented as an overall network average.'}

    @app.get('/api/network-tests/mine')
    def mine(limit:int=Query(30,ge=1,le=100),offset:int=Query(0,ge=0),user=Depends(current_user)):
        database.cleanup()
        with database.connect() as db:
            rows=db.execute('SELECT id,download_mbps,upload_mbps,ping_ms,connection_type,measurement_time,test_status,server_id FROM network_measurements WHERE user_id=? ORDER BY measurement_time DESC LIMIT ? OFFSET ?',(user['id'],limit,offset)).fetchall()
        return {'items':[dict(r) for r in rows],'limit':limit,'offset':offset}

    @app.delete('/api/network-tests/mine',status_code=204)
    def delete_mine(user=Depends(current_user)):
        with database.connect() as db: db.execute('DELETE FROM network_measurements WHERE user_id=?',(user['id'],))
        return Response(status_code=204)

    @app.delete('/api/auth/account',status_code=204)
    def delete_account(user=Depends(current_user)):
        with database.connect() as db: db.execute('DELETE FROM users WHERE id=?',(user['id'],))
        with lock:
            for key in list(sessions):
                if sessions[key]['user']==user['id']: del sessions[key]
        return Response(status_code=204)

    @app.get('/api/admin/overview')
    def admin_overview(user=Depends(current_user)):
        require_admin(user)
        with database.connect() as db:
            users_count = db.execute('SELECT count(*) FROM users').fetchone()[0]
            tests_count = db.execute('SELECT count(*) FROM network_measurements').fetchone()[0]
            shared = db.execute('SELECT count(*) FROM network_measurements WHERE cell_y IS NOT NULL').fetchone()[0]
            gemini = db.execute("SELECT value FROM app_settings WHERE key='gemini_api_key'").fetchone()
        return {
            'users': users_count,
            'measurements': tests_count,
            'shared_measurements': shared,
            'gemini_configured': bool(gemini and gemini['value']),
            'db_path': cfg.db,
        }

    @app.get('/api/admin/users')
    def admin_users(user=Depends(current_user)):
        require_admin(user)
        with database.connect() as db:
            rows = db.execute(
                '''SELECT u.id,u.phone,u.name,u.is_admin,
                          (SELECT count(*) FROM network_measurements m WHERE m.user_id=u.id) AS tests
                   FROM users u ORDER BY u.is_admin DESC, u.phone'''
            ).fetchall()
        return {'items':[{**dict(r),'is_admin':bool(r['is_admin'])} for r in rows]}

    @app.get('/api/admin/measurements')
    def admin_measurements(limit:int=Query(50,ge=1,le=200),offset:int=Query(0,ge=0),user=Depends(current_user)):
        require_admin(user)
        with database.connect() as db:
            rows = db.execute(
                '''SELECT m.id,m.user_id,u.phone,m.download_mbps,m.upload_mbps,m.ping_ms,m.connection_type,
                          m.cell_y,m.cell_x,m.measurement_time,m.test_status
                   FROM network_measurements m JOIN users u ON u.id=m.user_id
                   ORDER BY m.measurement_time DESC LIMIT ? OFFSET ?''',
                (limit, offset),
            ).fetchall()
        return {'items':[dict(r) for r in rows],'limit':limit,'offset':offset}

    @app.get('/api/admin/settings')
    def admin_settings_get(user=Depends(current_user)):
        require_admin(user)
        with database.connect() as db:
            row = db.execute("SELECT value FROM app_settings WHERE key='gemini_api_key'").fetchone()
        key = row['value'] if row else ''
        masked = (key[:4] + '…' + key[-4:]) if len(key) > 10 else ('مضبوط' if key else '')
        return {'gemini_api_key_set': bool(key), 'gemini_api_key_masked': masked}

    @app.put('/api/admin/settings')
    def admin_settings_put(data: AdminSettingsIn, user=Depends(current_user)):
        require_admin(user)
        key = data.gemini_api_key.strip()
        with database.connect() as db:
            if key:
                db.execute(
                    'INSERT INTO app_settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at',
                    ('gemini_api_key', key, time.time()),
                )
            else:
                db.execute("DELETE FROM app_settings WHERE key='gemini_api_key'")
        return {'ok': True, 'gemini_api_key_set': bool(key)}

    @app.post('/api/admin/analyze')
    async def admin_analyze(data: AnalyzeIn, user=Depends(current_user)):
        require_admin(user)
        with database.connect() as db:
            row = db.execute("SELECT value FROM app_settings WHERE key='gemini_api_key'").fetchone()
        if not row or not row['value']:
            raise HTTPException(400, 'أدخل مفتاح Gemini من إعدادات الإدارة أولًا')
        payload = {
            'contents': [{'parts': [{'text':
                'أنت مساعد تحليل شبكة اتصالات لحائل. أجب بالعربية باختصار ووضوح.\n\n' + data.text}]}],
        }
        url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent'
        try:
            async with httpx.AsyncClient(timeout=45) as client:
                response = await client.post(url, params={'key': row['value']}, json=payload)
        except httpx.HTTPError:
            raise HTTPException(502, 'تعذر الاتصال بخدمة Gemini')
        if response.status_code >= 400:
            raise HTTPException(502, 'رفض Gemini المفتاح أو الطلب؛ تحقق من المفتاح')
        body = response.json()
        try:
            text = body['candidates'][0]['content']['parts'][0]['text']
        except (KeyError, IndexError, TypeError):
            raise HTTPException(502, 'استجابة Gemini غير صالحة')
        return {'analysis': text}

    @app.delete('/api/admin/users/{user_id}', status_code=204)
    def admin_delete_user(user_id: str, user=Depends(current_user)):
        require_admin(user)
        if user_id == user['id']:
            raise HTTPException(400, 'لا يمكن حذف حساب المدير الحالي من هنا')
        with database.connect() as db:
            target = db.execute('SELECT is_admin FROM users WHERE id=?', (user_id,)).fetchone()
            if not target:
                raise HTTPException(404, 'المستخدم غير موجود')
            if target['is_admin']:
                raise HTTPException(400, 'لا يُحذف حساب مدير آخر من الواجهة')
            db.execute('DELETE FROM users WHERE id=?', (user_id,))
        return Response(status_code=204)

    return app

app=create_app()
