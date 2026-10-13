#!/usr/bin/env bash
# Install only the desktop release templates into a project-local data directory.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
version=4.4.1
archive="Godot_v${version}-stable_export_templates.tpz"
checksum=8f461c7d6e91a0fbabfc95b1e4ca70ff1732c6f2920956a16b086ec2a85b5f7e238baf4dbce60dcc5630fae3bcb9a1fa2ae2027b92cb495c02d082705715e441
data_dir="${XDG_DATA_HOME:-$PWD/build/godot-data}"
destination="$data_dir/godot/export_templates/${version}.stable"
mkdir -p build/downloads "$destination"
if [[ ! -f "build/downloads/$archive" ]]; then
  curl -fL --retry 3 "https://github.com/godotengine/godot-builds/releases/download/${version}-stable/$archive" \
    -o "build/downloads/$archive.part"
  mv "build/downloads/$archive.part" "build/downloads/$archive"
fi
printf '%s  %s\n' "$checksum" "build/downloads/$archive" | sha512sum --check
unzip -jo "build/downloads/$archive" \
  templates/linux_release.x86_64 templates/windows_release_x86_64.exe templates/version.txt \
  -d "$destination"
chmod +x "$destination/linux_release.x86_64"
echo "Desktop templates installed in $destination"
