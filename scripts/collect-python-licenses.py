"""Preserve installed distribution license and copyright notices for release artifacts."""
import importlib.metadata
import json
import pathlib
import sys

output = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/licenses/python")
output.mkdir(parents=True, exist_ok=True)
inventory = []
for distribution in importlib.metadata.distributions():
    metadata = distribution.metadata
    name = f"{metadata['Name']}@{distribution.version}"
    record = {
        "name": name,
        "license": metadata.get("License-Expression") or metadata.get("License") or "REVIEW REQUIRED",
        "notices": [],
    }
    target = output / name
    target.mkdir(exist_ok=True)
    for file in distribution.files or []:
        if any(part.lower().startswith(("license", "licence", "copying", "notice", "copyright"))
               for part in file.parts):
            source = pathlib.Path(distribution.locate_file(file))
            if source.is_file():
                destination = target / str(file).replace("/", "__")
                destination.write_bytes(source.read_bytes())
                record["notices"].append(str(file))
    inventory.append(record)
(output / "inventory.json").write_text(json.dumps(inventory, indent=2))
print(f"Collected notices for {len(inventory)} Python distributions")
