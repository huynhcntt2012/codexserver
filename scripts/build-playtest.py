"""Export standalone Windows/Linux playtest ZIPs with licenses and provenance."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "build" / "playtest"


def run(command, env=None):
    result = subprocess.run(
        command, cwd=ROOT, env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, timeout=180,
    )
    print(result.stdout, end="")
    if result.returncode or "SCRIPT ERROR" in result.stdout or "ERROR:" in result.stdout:
        raise SystemExit(f"Command failed: {command[0]}")
    return result.stdout.strip()


def main():
    godot = os.environ.get("GODOT", "godot")
    env = os.environ.copy()
    env.setdefault("XDG_DATA_HOME", str(ROOT / "build" / "godot-data"))
    version = run([godot, "--version"], env)
    if not version.startswith("4.4.1.stable."):
        raise SystemExit("Use the pinned Godot 4.4.1 stable editor.")
    commit = run(["git", "rev-parse", "HEAD"])
    dirty = bool(run(["git", "status", "--porcelain"]))
    OUTPUT.mkdir(parents=True, exist_ok=True)
    run([godot, "--headless", "--path", "apps/client", "--editor", "--quit"], env)
    checksums = []
    for preset, platform, executable in (
        ("Linux", "linux-x86_64", "suni-bomb-arena.x86_64"),
        ("Windows", "windows-x86_64", "suni-bomb-arena.exe"),
    ):
        name = f"suni-bomb-arena-{platform}"
        with tempfile.TemporaryDirectory(prefix="suni-export-", dir=OUTPUT) as stage:
            package = Path(stage) / name
            package.mkdir()
            binary = package / executable
            run([
                godot, "--headless", "--path", "apps/client", "--export-release",
                preset, str(binary),
            ], env)
            if not binary.is_file() or not binary.with_suffix(".pck").is_file():
                raise SystemExit(f"Incomplete {preset} export")
            if preset == "Linux":
                binary.chmod(0o755)
                run([str(binary), "--headless", "--quit-after", "3"], env)
            shutil.copy2(ROOT / "docs" / "PLAYTEST_PLAYER.md", package / "README.txt")
            shutil.copytree(ROOT / "apps" / "client" / "licenses", package / "licenses")
            manifest = {"commit": commit, "dirty": dirty, "godot": version, "platform": platform}
            (package / "BUILD.json").write_text(
                json.dumps(manifest, indent=2) + "\n", encoding="utf-8",
            )
            staged_archive = Path(stage) / f"{name}.zip"
            with zipfile.ZipFile(staged_archive, "w", zipfile.ZIP_DEFLATED) as archive:
                for path in sorted(package.rglob("*")):
                    if path.is_file():
                        archive.write(path, path.relative_to(stage))
            digest = hashlib.sha256(staged_archive.read_bytes()).hexdigest()
            archive_path = OUTPUT / staged_archive.name
            staged_archive.replace(archive_path)
            checksums.append(f"{digest}  {archive_path.name}")
            print(f"Created {archive_path}")
    (OUTPUT / "SHA256SUMS.txt").write_text("\n".join(checksums) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
