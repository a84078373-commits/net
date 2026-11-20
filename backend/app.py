"""SmartCare Flask entrypoint: website + JSON API for the mobile app.

Run locally (standalone website):
  python backend/run_web.py          # or double-click backend/run_web.bat

Production (Render):
  gunicorn -b 0.0.0.0:$PORT -w 1 --threads 8 backend.flask_app:app
"""
from backend.core import (
    MIB,
    QUALITY,
    Settings,
    cell_for,
    classify,
)
from backend.flask_app import create_app, app

__all__ = [
    'MIB',
    'QUALITY',
    'Settings',
    'app',
    'cell_for',
    'classify',
    'create_app',
]
