"""Run the SmartCare website on its own — no Docker, gunicorn, or Flutter needed.

  python backend/run_web.py             # http://localhost:8765 (this computer only)
  python backend/run_web.py --lan       # also reachable from phones on the same Wi-Fi
  python backend/run_web.py --port 9000 --no-browser

Local runs enable the speed test against this machine (loopback), so results
measure the path to this computer, not the public internet.
"""
from __future__ import annotations

import argparse
import os
import socket
import sys
import threading
import webbrowser
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


def load_dotenv(path: Path) -> None:
    """Load KEY=VALUE lines into os.environ without overriding existing values."""
    if not path.is_file():
        return
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        key, _, value = line.partition('=')
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key:
            os.environ.setdefault(key, value)


def lan_address() -> str | None:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(('10.255.255.255', 1))
            return s.getsockname()[0]
    except OSError:
        return None


def main() -> None:
    parser = argparse.ArgumentParser(description='Run the SmartCare website standalone.')
    parser.add_argument('--port', type=int, default=int(os.getenv('PORT', '8765')))
    parser.add_argument('--lan', action='store_true', help='listen on all interfaces (0.0.0.0)')
    parser.add_argument('--no-browser', action='store_true', help='do not open the browser')
    args = parser.parse_args()

    load_dotenv(Path(__file__).resolve().parent / '.env')

    local_url = f'http://localhost:{args.port}'
    os.environ.setdefault('SMARTCARE_PUBLIC_ORIGIN', local_url)
    os.environ.setdefault('SMARTCARE_SPEED_ENABLED', '1')
    os.environ.setdefault(
        'SMARTCARE_CORS',
        f'{local_url},http://127.0.0.1:{args.port},http://localhost:8080,http://127.0.0.1:8080',
    )

    from backend.flask_app import app

    host = '0.0.0.0' if args.lan else '127.0.0.1'
    print(f'\n  SmartCare web:  {local_url}', flush=True)
    if args.lan and (ip := lan_address()):
        print(f'  On your network: http://{ip}:{args.port}', flush=True)
    print('  Press Ctrl+C to stop.\n', flush=True)

    if not args.no_browser:
        threading.Timer(1.5, webbrowser.open, args=(local_url,)).start()
    app.run(host=host, port=args.port, threaded=True, debug=False, use_reloader=False)


if __name__ == '__main__':
    main()
