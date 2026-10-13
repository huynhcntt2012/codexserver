#!/usr/bin/env bash
set -euo pipefail
version=4.4.1
destination="${1:-/tmp/suni-godot}"
mkdir -p "$destination"
curl -fL --retry 3 "https://github.com/godotengine/godot/releases/download/${version}-stable/Godot_v${version}-stable_linux.x86_64.zip" -o "$destination/godot.zip"
unzip -o "$destination/godot.zip" -d "$destination"
chmod +x "$destination/Godot_v${version}-stable_linux.x86_64"
ln -sf "Godot_v${version}-stable_linux.x86_64" "$destination/godot"
