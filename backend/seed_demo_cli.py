"""Re-seed Hail demo data.

  python -m backend.seed_demo_cli
  python -m backend.seed_demo_cli --force
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend.core import Database, load_settings
from backend.demo_seed import print_demo_credentials, seed_demo_hail


def main() -> None:
    parser = argparse.ArgumentParser(description='Seed SmartCare Hail demo data')
    parser.add_argument(
        '--force',
        action='store_true',
        help='wipe previous demo phones and re-insert',
    )
    args = parser.parse_args()
    settings = load_settings()
    db = Database(settings.db)
    summary = seed_demo_hail(db, force=args.force)
    print_demo_credentials(summary)
    print(
        f"  sites={summary.get('sites')} complaints={summary.get('complaints')}",
        flush=True,
    )


if __name__ == '__main__':
    main()
