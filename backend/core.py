"""Shared SmartCare settings, database, and quality helpers."""
from __future__ import annotations

import hashlib
import json
import math
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager, suppress
from dataclasses import dataclass
from pathlib import Path

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
    secret_key: str = os.getenv('SMARTCARE_SECRET', 'smartcare-dev-secret-change-me')


def cell_for(lat, lon):
    step = QUALITY['cell_degrees']
    return math.floor((lat + 1e-9) / step), math.floor((lon + 1e-9) / step)


def cell_id(y, x):
    return f'g1_{y}_{x}'


def cell_bounds(y, x):
    step = QUALITY['cell_degrees']
    return [round(x * step, 6), round(y * step, 6), round((x + 1) * step, 6), round((y + 1) * step, 6)]


def classify(value, metric):
    a, b, c = QUALITY[metric]
    if metric == 'ping':
        return 'good' if value <= a else 'moderate' if value <= b else 'poor' if value <= c else 'very_poor'
    return 'very_poor' if value < a else 'poor' if value < b else 'moderate' if value < c else 'good'


def load_settings(**overrides) -> Settings:
    base = Settings(
        db=os.getenv('SMARTCARE_DB', Settings.db),
        public_origin=os.getenv('SMARTCARE_PUBLIC_ORIGIN', ''),
        speed_enabled=os.getenv('SMARTCARE_SPEED_ENABLED') == '1',
        cors_origins=tuple(
            os.getenv(
                'SMARTCARE_CORS',
                'http://localhost:8080,http://127.0.0.1:8080',
            ).split(',')
        ),
        secret_key=os.getenv('SMARTCARE_SECRET', Settings.secret_key),
    )
    for key, value in overrides.items():
        setattr(base, key, value)
    return base


class Database:
    def __init__(self, path):
        Path(path).parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.path = path
        with self.connect() as db:
            db.executescript(
                '''
              PRAGMA journal_mode=WAL;
              CREATE TABLE IF NOT EXISTS users(id TEXT PRIMARY KEY, phone TEXT UNIQUE NOT NULL, name TEXT NOT NULL, salt TEXT NOT NULL, password_hash TEXT NOT NULL, hash_iterations INTEGER NOT NULL DEFAULT 600000, is_admin INTEGER NOT NULL DEFAULT 0, created_at REAL NOT NULL DEFAULT 0);
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
            '''
            )
            cols = {r[1] for r in db.execute('PRAGMA table_info(users)')}
            if 'hash_iterations' not in cols:
                db.execute(
                    'ALTER TABLE users ADD COLUMN hash_iterations INTEGER NOT NULL DEFAULT 310000'
                )
            if 'is_admin' not in cols:
                db.execute(
                    'ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0'
                )
            if 'created_at' not in cols:
                db.execute(
                    'ALTER TABLE users ADD COLUMN created_at REAL NOT NULL DEFAULT 0'
                )
                db.execute(
                    'UPDATE users SET created_at=? WHERE created_at=0 OR created_at IS NULL',
                    (time.time(),),
                )
            for col, decl in (
                ('first_name', 'TEXT NOT NULL DEFAULT \'\''),
                ('second_name', 'TEXT NOT NULL DEFAULT \'\''),
                ('family_name', 'TEXT NOT NULL DEFAULT \'\''),
                ('gender', 'TEXT NOT NULL DEFAULT \'\''),
            ):
                if col not in cols:
                    db.execute(f'ALTER TABLE users ADD COLUMN {col} {decl}')
        if os.name == 'posix':
            with suppress(OSError):
                os.chmod(path, 0o600)

    def seed_admin(self, phone='0552515874', password='123456', name='مدير النظام'):
        salt = secrets.token_hex(16)
        digest = hashlib.pbkdf2_hmac(
            'sha256', password.encode(), bytes.fromhex(salt), 600000
        ).hex()
        with self.connect() as db:
            row = db.execute('SELECT id FROM users WHERE phone=?', (phone,)).fetchone()
            if row:
                db.execute(
                    'UPDATE users SET name=?, salt=?, password_hash=?, hash_iterations=600000, is_admin=1 WHERE phone=?',
                    (name, salt, digest, phone),
                )
            else:
                db.execute(
                    'INSERT INTO users(id,phone,name,salt,password_hash,hash_iterations,is_admin,created_at) VALUES(?,?,?,?,?,?,1,?)',
                    (
                        secrets.token_urlsafe(18),
                        phone,
                        name,
                        salt,
                        digest,
                        600000,
                        time.time(),
                    ),
                )
            if os.getenv('SMARTCARE_GEMINI_API_KEY'):
                db.execute(
                    'INSERT INTO app_settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at',
                    (
                        'gemini_api_key',
                        os.getenv('SMARTCARE_GEMINI_API_KEY'),
                        time.time(),
                    ),
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
            db.execute(
                'DELETE FROM network_measurements WHERE measurement_time < ?',
                (time.time() - QUALITY['retention_days'] * 86400,),
            )
            db.execute('DELETE FROM auth_sessions WHERE expires < ?', (time.time(),))
