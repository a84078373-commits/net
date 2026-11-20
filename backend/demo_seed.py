"""Seed a rich Hail demo: users, measurements, complaints across many districts.

Idempotent unless force=True. Safe for local demos — clearly tagged demo phones.
"""
from __future__ import annotations

import hashlib
import random
import secrets
import time
from typing import TYPE_CHECKING

from backend.core import QUALITY, cell_for

if TYPE_CHECKING:
    from backend.core import Database

DEMO_FLAG = 'demo_hail_seed_v4'
DEMO_PASSWORD = 'demo1234'
# Primary demo account for the user to try.
DEMO_LOGIN_PHONE = '0501234567'
DEMO_LOGIN_NAME = 'مستخدم تجريبي'

# Extra synthetic users (contribute to public heat / radar).
DEMO_USERS = [
    (DEMO_LOGIN_PHONE, DEMO_LOGIN_NAME, False),
    ('0501111001', 'أحمد الحائلي', False),
    ('0501111002', 'نورة الشمري', False),
    ('0501111003', 'فهد العتيبي', False),
    ('0501111004', 'سارة المطيري', False),
    ('0501111005', 'خالد الرشيد', False),
    ('0501111006', 'منال القحطاني', False),
    ('0501111007', 'عبدالله العنزي', False),
    ('0501111008', 'ريم الدوسري', False),
    ('0501111009', 'يوسف السبيعي', False),
    ('0501111010', 'هند الزامل', False),
    ('0501111011', 'فني ميداني', False),
]


def _hash_password(password: str) -> tuple[str, str]:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac(
        'sha256', password.encode(), bytes.fromhex(salt), 600000
    ).hex()
    return salt, digest


def _ensure_user(db, phone: str, name: str, *, is_admin: int = 0) -> str:
    row = db.execute('SELECT id FROM users WHERE phone=?', (phone,)).fetchone()
    if row:
        return row['id']
    salt, digest = _hash_password(DEMO_PASSWORD)
    uid = secrets.token_urlsafe(18)
    parts = name.split(None, 2)
    first = parts[0] if parts else name
    second = parts[1] if len(parts) > 1 else ''
    family = parts[2] if len(parts) > 2 else ''
    db.execute(
        '''INSERT INTO users(
             id,phone,name,salt,password_hash,hash_iterations,is_admin,created_at,
             first_name,second_name,family_name,gender
           ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',
        (
            uid,
            phone,
            name,
            salt,
            digest,
            600000,
            is_admin,
            time.time() - random.uniform(3, 40) * 86400,
            first,
            second,
            family,
            random.choice(['male', 'female', '']),
        ),
    )
    return uid


def _hail_sites() -> list[dict]:
    """Named districts inside QUALITY bounds with quality bias."""
    west, south, east, north = QUALITY['bounds']
    # Relative positions across Hail — denser urban core + outskirts.
    sites = [
        ('وسط حائل', 0.50, 0.50, 'good'),
        ('الزهرة', 0.55, 0.48, 'good'),
        ('ضاحية الملك فهد', 0.62, 0.66, 'good'),
        ('المنتزه', 0.46, 0.52, 'moderate'),
        ('الخزامى', 0.58, 0.55, 'good'),
        ('السمراء', 0.42, 0.45, 'moderate'),
        ('النقرة', 0.38, 0.58, 'poor'),
        ('مطار حائل', 0.72, 0.62, 'moderate'),
        ('الجامعة', 0.60, 0.40, 'good'),
        ('الصناعية', 0.30, 0.35, 'poor'),
        ('شمال حائل', 0.52, 0.78, 'moderate'),
        ('جنوب حائل', 0.50, 0.22, 'poor'),
        ('شرق حائل', 0.82, 0.50, 'moderate'),
        ('الشفا', 0.65, 0.30, 'good'),
        ('الورود', 0.48, 0.60, 'good'),
        ('العزيزية', 0.40, 0.40, 'moderate'),
        ('المطار', 0.70, 0.55, 'poor'),
        ('المحطة', 0.45, 0.35, 'moderate'),
        ('النهضة', 0.62, 0.48, 'good'),
        ('الفيصلية', 0.54, 0.42, 'good'),
        ('النسيم', 0.58, 0.68, 'moderate'),
    ]
    out = []
    for name, hx, vy, bias in sites:
        lon = west + hx * (east - west)
        lat = south + vy * (north - south)
        # Small cluster of cells around each district.
        for dx in (-0.01, 0.0, 0.01):
            for dy in (-0.01, 0.0, 0.01):
                if abs(dx) + abs(dy) == 0.02 and random.random() < 0.35:
                    continue
                clat = lat + dy
                clon = lon + dx
                if not (south <= clat <= north and west <= clon <= east):
                    continue
                y, x = cell_for(clat, clon)
                out.append({'name': name, 'lat': clat, 'lon': clon, 'y': y, 'x': x, 'bias': bias})
    # Deduplicate cell keys keeping first district name.
    seen = {}
    for s in out:
        key = (s['y'], s['x'])
        if key not in seen:
            seen[key] = s
    return list(seen.values())


def _sample_speeds(bias: str, rng: random.Random) -> tuple[float, float, float]:
    """Return download, upload, ping matching quality bias."""
    if bias == 'good':
        dl = rng.uniform(55, 180)
        ul = rng.uniform(12, 45)
        ping = rng.uniform(18, 48)
    elif bias == 'moderate':
        dl = rng.uniform(18, 48)
        ul = rng.uniform(4, 12)
        ping = rng.uniform(55, 95)
    elif bias == 'poor':
        dl = rng.uniform(6, 14)
        ul = rng.uniform(1.2, 2.8)
        ping = rng.uniform(110, 180)
    else:  # very_poor
        dl = rng.uniform(1.2, 4.8)
        ul = rng.uniform(0.4, 1.0)
        ping = rng.uniform(190, 320)
    return round(dl, 2), round(ul, 2), round(ping, 1)


def seed_demo_hail(database: Database, *, force: bool = False) -> dict:
    """Populate Hail with demo users + dense measurements. Returns summary counts."""
    rng = random.Random(42)
    now = time.time()

    with database.connect() as db:
        flag = db.execute(
            "SELECT value FROM app_settings WHERE key=?", (DEMO_FLAG,)
        ).fetchone()
        if flag and not force:
            users = db.execute(
                "SELECT count(*) FROM users WHERE phone LIKE '0501111%' OR phone=?",
                (DEMO_LOGIN_PHONE,),
            ).fetchone()[0]
            meas = db.execute('SELECT count(*) FROM network_measurements').fetchone()[0]
            return {
                'skipped': True,
                'demo_phone': DEMO_LOGIN_PHONE,
                'demo_password': DEMO_PASSWORD,
                'users': int(users),
                'measurements': int(meas),
            }

        if force:
            # Remove previous demo-tagged rows only (phones we own).
            phones = [p for p, _, _ in DEMO_USERS]
            for phone in phones:
                row = db.execute('SELECT id FROM users WHERE phone=?', (phone,)).fetchone()
                if not row:
                    continue
                uid = row['id']
                db.execute('DELETE FROM service_complaints WHERE user_id=?', (uid,))
                db.execute('DELETE FROM alert_subscriptions WHERE user_id=?', (uid,))
                db.execute('DELETE FROM network_measurements WHERE user_id=?', (uid,))
                db.execute('DELETE FROM users WHERE id=?', (uid,))

        user_ids = []
        for phone, name, admin in DEMO_USERS:
            user_ids.append(_ensure_user(db, phone, name, is_admin=1 if admin else 0))

        sites = _hail_sites()
        conns = ['wifi', 'cellular', 'cellular', 'wifi', 'ethernet']
        inserted = 0
        complaints = 0

        # Spread samples over last 10 days + strong recent window for radar.
        for site in sites:
            # Pick 4–6 contributors so public heat clears privacy thresholds.
            contributors = rng.sample(user_ids, k=min(6, len(user_ids)))
            for uid in contributors:
                samples = rng.randint(2, 4)
                for s_i in range(samples):
                    # Mix historical + last 3 hours (for outage radar).
                    if site['bias'] in ('poor', 'very_poor') and s_i == 0:
                        age_h = rng.uniform(0.2, 2.5)
                    elif s_i == samples - 1:
                        age_h = rng.uniform(1, 48)
                    else:
                        age_h = rng.uniform(24, 240)
                    ts = now - age_h * 3600
                    hour_bucket = int(ts // 3600)
                    dl, ul, ping = _sample_speeds(site['bias'], rng)
                    # Slight jitter per sample.
                    dl = max(0.5, dl * rng.uniform(0.85, 1.15))
                    ul = max(0.2, ul * rng.uniform(0.85, 1.15))
                    ping = max(10.0, ping * rng.uniform(0.9, 1.12))
                    conn = rng.choice(conns)
                    mid = secrets.token_urlsafe(14)
                    sid = secrets.token_urlsafe(18)
                    try:
                        db.execute(
                            '''INSERT INTO network_measurements(
                                 id,user_id,download_mbps,upload_mbps,ping_ms,
                                 jitter_ms,packet_loss_percent,connection_type,connection_source,
                                 carrier_name,carrier_source,cell_y,cell_x,location_accuracy_m,
                                 measurement_time,created_at,test_status,server_id,session_id,hour_bucket
                               ) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
                            (
                                mid,
                                uid,
                                round(dl, 2),
                                round(ul, 2),
                                round(ping, 1),
                                round(rng.uniform(1, 12), 2),
                                round(rng.uniform(0, 2.5), 2),
                                conn,
                                'os_interface' if conn != 'unknown' else 'user',
                                None,
                                None,
                                site['y'],
                                site['x'],
                                round(rng.uniform(8, 45), 1),
                                ts,
                                ts,
                                'completed',
                                'demo-seed',
                                sid,
                                hour_bucket,
                            ),
                        )
                        inserted += 1
                    except Exception:
                        # UNIQUE(user,cell,hour) collision — skip.
                        continue

            # Complaints on weak districts (feeds outage radar).
            if site['bias'] in ('poor', 'very_poor') and rng.random() < 0.75:
                for _ in range(rng.randint(1, 3)):
                    uid = rng.choice(contributors)
                    cid = secrets.token_urlsafe(12)
                    cts = now - rng.uniform(0.3, 5) * 3600
                    db.execute(
                        '''INSERT INTO service_complaints(
                             id,user_id,cell_y,cell_x,category,severity,note,created_at
                           ) VALUES(?,?,?,?,?,?,?,?)''',
                        (
                            cid,
                            uid,
                            site['y'],
                            site['x'],
                            rng.choice(['outage', 'slow', 'no_signal']),
                            4 if site['bias'] == 'very_poor' else 3,
                            f"بلاغ تجريبي — {site['name']}",
                            cts,
                        ),
                    )
                    complaints += 1

        # Subscribe demo user to one weak cell.
        weak = next((s for s in sites if s['bias'] == 'very_poor'), sites[0])
        demo_uid = user_ids[0]
        try:
            db.execute(
                '''INSERT INTO alert_subscriptions(
                     id,user_id,cell_y,cell_x,channel,active,created_at
                   ) VALUES(?,?,?,?, 'inapp', 1, ?)
                   ON CONFLICT(user_id, cell_y, cell_x, channel) DO UPDATE SET active=1''',
                (secrets.token_urlsafe(12), demo_uid, weak['y'], weak['x'], now),
            )
        except Exception:
            pass

        db.execute(
            '''INSERT INTO app_settings(key,value,updated_at) VALUES(?,?,?)
               ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at''',
            (DEMO_FLAG, '1', now),
        )

        return {
            'skipped': False,
            'demo_phone': DEMO_LOGIN_PHONE,
            'demo_password': DEMO_PASSWORD,
            'users': len(user_ids),
            'sites': len(sites),
            'measurements': inserted,
            'complaints': complaints,
        }


def print_demo_credentials(summary: dict) -> None:
    print(
        f"[smartcare] demo login phone={summary.get('demo_phone')} "
        f"password={summary.get('demo_password')} "
        f"users={summary.get('users')} measurements={summary.get('measurements')} "
        f"{'(already seeded)' if summary.get('skipped') else '(seeded)'}",
        flush=True,
    )
