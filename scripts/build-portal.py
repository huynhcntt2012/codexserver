#!/usr/bin/env python3
"""Writes the promotion website's game data (docs/PORTAL.md).

apps/web/public/data/game.json is generated from the game's own files
(characters, built-in maps, battle items), so the site never drifts from the game.
Run after changing those files; the web image copies the art (see apps/web/Dockerfile).
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PRACTICE = ROOT / "apps/practice"
OUT = ROOT / "apps/web/public/data/game.json"
QUICK_SLOTS = ["throw_bomb", "dart", "blue_shield", "speed_shoes", "freeze_bomb", "push_glove"]
ROLES = {
    "bombo": "Thủ lĩnh",
    "mimi": "Nhanh nhẹn",
    "zin": "Sức nổ lớn",
    "lala": "Hỗ trợ",
    "kai": "Chiến thuật",
}


def asset(path: str) -> str:
    """res://assets/x.png -> the copy served by the web image."""
    return "/assets/" + path.removeprefix("res://assets/")


def sentence(text: str) -> str:
    return text[:1].upper() + text[1:]


def main() -> None:
    characters = json.loads((PRACTICE / "data/ui/characters.json").read_text())
    items = json.loads((PRACTICE / "data/ui/items.json").read_text())
    by_id = {i["id"]: i for i in items}
    maps = []
    for path in sorted((PRACTICE / "levels").glob("*.json")):
        level = json.loads(path.read_text())
        maps.append(
            {
                "id": level["id"],
                "name": level["name"].title(),
                "subtitle": level.get("subtitle", ""),
                "story": level.get("story", ""),
                "size": f"{level['columns']}×{level['rows']}",
                "players": "2–4",
                "image": f"/assets/level_previews/{level['id']}.png",
                "pack": level.get("pack_id", "999"),
            }
        )
    maps.sort(key=lambda m: (m["pack"], m["id"]))
    data = {
        "characters": [
            {
                "id": c["id"],
                "name": c["name"].title(),
                "role": ROLES.get(c["id"], ""),
                "desc": sentence(c.get("desc", "")),
                "stats": c.get("stats", {}),
                "portrait": asset(c["portrait"]),
            }
            for c in characters
        ],
        "maps": maps,
        "items": [
            {
                "id": i,
                "slot": n + 1,
                "name": by_id[i]["name"].split(" ×")[0],
                "desc": sentence(by_id[i].get("description", "").removeprefix("Ctrl: ")),
                "icon": asset(by_id[i]["icon"]),
            }
            for n, i in enumerate(QUICK_SLOTS)
        ],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"{OUT.relative_to(ROOT)}: {len(data['characters'])} characters, {len(maps)} maps")


if __name__ == "__main__":
    main()
