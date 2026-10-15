"""Export the supplied Step 3 practice mode for web and Windows using Godot 4.4.1."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "apps/practice"
WEB = ROOT / "apps/web/public/practice/engine"
OUTPUT = ROOT / "build/practice"


def run(args, env):
    result = subprocess.run(args, cwd=ROOT, env=env, capture_output=True, text=True, timeout=240)
    if result.returncode or "SCRIPT ERROR" in result.stdout + result.stderr or "ERROR:" in result.stdout + result.stderr:
        raise SystemExit(result.stdout + result.stderr)
    return result.stdout.strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-only", action="store_true", help="Skip Windows packaging")
    args = parser.parse_args()
    env = os.environ.copy()
    env.setdefault("XDG_DATA_HOME", str(ROOT / "build/godot-data"))
    godot = env.get("GODOT", "godot")
    version = run([godot, "--version"], env)
    if not version.startswith("4.4.1.stable."):
        raise SystemExit("Godot 4.4.1 stable is required")
    manifest = {
        "commit": run(["git", "rev-parse", "HEAD"], env),
        "dirty": bool(run(["git", "status", "--porcelain"], env)),
        "godot": version,
        "mode": "single-player-three-bots",
    }
    WEB.mkdir(parents=True, exist_ok=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    base = [godot, "--headless", "--path", str(PROJECT)]
    run(base + ["--editor", "--quit"], env)
    run(base + ["--export-release", "Web", str(WEB / "index.html")], env)
    # Keep the official loader, but externalize its inline code for a strict CSP.
    html = (WEB / "index.html").read_text()
    styles = re.findall(r"<style>(.*?)</style>", html, re.S)
    scripts = re.findall(r"<script>(.*?)</script>", html, re.S)
    if len(styles) != 1 or len(scripts) != 1:
        raise SystemExit("Unexpected Godot HTML shell; review CSP extraction")
    (WEB / "shell.css").write_text(styles[0])
    (WEB / "boot.js").write_text(scripts[0])
    html = re.sub(r"<style>.*?</style>", '<link rel="stylesheet" href="shell.css">', html, flags=re.S)
    html = re.sub(r"<script>.*?</script>", '<script src="boot.js"></script>', html, flags=re.S)
    (WEB / "index.html").write_text(html)
    shutil.copytree(PROJECT / "licenses", WEB / "licenses", dirs_exist_ok=True)
    (WEB / "BUILD.json").write_text(json.dumps(manifest, indent=2) + "\n")
    if args.web_only:
        print(f"Web: {WEB}\nSource: {manifest}")
        return
    package = OUTPUT / "suni-bot-arena-windows-x86_64"
    package.mkdir(exist_ok=True)
    run(base + ["--export-release", "Windows", str(package / "suni-bot-arena.exe")], env)
    shutil.copytree(PROJECT / "licenses", package / "licenses", dirs_exist_ok=True)
    shutil.copy2(ROOT / "docs/PRACTICE.md", package / "README.txt")
    (package / "BUILD.json").write_text(json.dumps(manifest, indent=2) + "\n")
    archive = OUTPUT / f"{package.name}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(package.rglob("*")):
            if path.is_file():
                bundle.write(path, path.relative_to(OUTPUT))
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (OUTPUT / "SHA256SUMS.txt").write_text(f"{digest}  {archive.name}\n")
    print(f"Web: {WEB}\nWindows: {archive}\nSource: {manifest}")


if __name__ == "__main__":
    main()
