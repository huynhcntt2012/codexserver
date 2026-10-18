#!/usr/bin/env python3
"""Publishes a Windows build for the website's Download page (docs/PORTAL.md).

Copies the ZIP into the releases folder under a versioned name and writes
latest.json (version, size, SHA-256, date) next to it, plus history.json for the
Admin Portal. nginx serves the folder at
/releases/ (compose: RELEASES_DIR, default ./build/releases). The previous files
stay, so rolling back = run again with the older ZIP.

  python3 scripts/publish-release.py build/practice/suni-bot-arena-windows-x86_64.zip \\
      --version 0.2.0-beta --notes "Vật phẩm trong trận, thú cưỡi"
"""

import argparse
import hashlib
import json
import os
import shutil
from datetime import UTC, datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("zip", type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--notes", default="")
    parser.add_argument("--dir", type=Path, default=Path(os.environ.get("RELEASES_DIR", ROOT / "build/releases")))
    args = parser.parse_args()
    if not args.zip.is_file() or args.zip.suffix != ".zip":
        parser.error(f"{args.zip} is not a .zip file")
    if not all(c.isalnum() or c in ".-" for c in args.version):
        parser.error("version: letters, digits, dot and dash only")
    args.dir.mkdir(parents=True, exist_ok=True)
    name = f"bupbup-windows-{args.version}.zip"
    target = args.dir / name
    shutil.copyfile(args.zip, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    release = {
        "platform": "windows",
        "version": args.version,
        "status": "published",
        "fileName": name,
        "fileSizeBytes": target.stat().st_size,
        "downloadUrl": f"/releases/{name}",
        "sha256": digest,
        "publishedAt": datetime.now(UTC).replace(microsecond=0).isoformat(),
        "notes": args.notes,
    }
    latest = args.dir / "latest.json"
    temp = latest.with_suffix(".tmp")
    temp.write_text(json.dumps(release, ensure_ascii=False, indent=2) + "\n")
    temp.replace(latest)
    # Release history for the Admin Portal (Website > Bản tải), newest last.
    history_path = args.dir / "history.json"
    try:
        history = json.loads(history_path.read_text())
    except (OSError, ValueError):
        history = []
    if not isinstance(history, list):
        history = []
    history.append(release)
    temp = history_path.with_suffix(".tmp")
    temp.write_text(json.dumps(history[-100:], ensure_ascii=False, indent=2) + "\n")
    temp.replace(history_path)
    print(f"{target} {release['fileSizeBytes']} bytes sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
