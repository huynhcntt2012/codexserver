"""Fail CI on Godot script errors, including editor errors that return code 0."""
import os
import subprocess
import sys

binary = os.environ.get("GODOT", "godot")
for args in (["--editor", "--quit"], ["--quit-after", "3"]):
    result = subprocess.run(
        [binary, "--headless", "--path", "apps/client", *args],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60,
    )
    print(result.stdout)
    if result.returncode or "SCRIPT ERROR" in result.stdout or "Parse Error" in result.stdout:
        sys.exit(1)
