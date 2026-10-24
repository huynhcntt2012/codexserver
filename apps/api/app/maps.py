"""Admin-made maps: draft -> validate -> publish, served to clients and the arena.

The 15 built-in maps ship with the game (apps/practice/levels, apps/arena/src/maps.ts).
Admins add more as JSON (see docs/map-template.json). Every map is validated here
(shape, border, spawns, an escape from each start, reachability, known art keys) and
published maps are served by ``GET /v1/maps`` in the same shape as the game's level
files. The arena re-checks the layout before it builds a room on a published map.
"""

import hashlib
import json
from collections import deque
from datetime import UTC, datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Header, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import JSON, DateTime, Integer, String, select
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import Operator, Reader, audit
from app.main import Base, Db

router = APIRouter()

# Ids of the maps built into the client and the arena; admin maps cannot reuse them.
BUILTIN_IDS = frozenset(
    "park frost coast pastry forest harbor station clock crystal market sky volcano star"
    " factory moon".split()
)
# Art the PC client ships (apps/practice/assets); a map may only reference these.
FLOORS = frozenset(
    "grass sand snow lava pastry forest harbor station clock crystal market sky volcano"
    " star factory moon".split()
)
WALLS = frozenset({"stone_wall", "special_wall", "shrub"})
CRATES = frozenset({"wood_crate", "barrel", "metal_barrel", "shrub"})
BOMBS = frozenset(
    {"classic_blue", "ice", "piercing_red", "pink", "star", "strong_black", "water_blue"}
)
EFFECTS = frozenset({"water_splash", "ice", "fire_horizontal", "fire_vertical", "heart"})
TIERS = {"Dễ": (0.39, 3.0), "Trung bình": (0.34, 2.6), "Khó": (0.29, 2.1)}
DIRS = ((0, 1), (0, -1), (1, 0), (-1, 0))

TEMPLATE = {
    "id": "candy_maze",
    "name": "Mê Cung Kẹo",
    "tier": "Trung bình",
    "region": "Khu vườn kẹo",
    "story": "Mô tả ngắn hiện ở thẻ bản đồ (không bắt buộc).",
    "art": {
        "floor": "pastry",
        "wall": "stone_wall",
        "crate": "wood_crate",
        "bomb": "pink",
        "fx": "heart",
    },
    "layout": [
        "#################",
        "#...C.C...C.C...#",
        "#.#.#C#.#.#C#.#.#",
        "#.C.....C.....C.#",
        "#C#.#.#C#C#.#.#C#",
        "#..C.C.....C.C..#",
        "#.#C#.#.#.#.#C#.#",
        "#..C.C.....C.C..#",
        "#C#.#.#C#C#.#.#C#",
        "#.C.....C.....C.#",
        "#.#.#C#.#.#C#.#.#",
        "#...C.C...C.C...#",
        "#################",
    ],
}


def now() -> datetime:
    return datetime.now(UTC)


class GameMap(Base):
    __tablename__ = "game_maps"
    id: Mapped[str] = mapped_column(String(24), primary_key=True)
    name: Mapped[str] = mapped_column(String(40))
    tier: Mapped[str] = mapped_column(String(16))
    region: Mapped[str] = mapped_column(String(60), default="")
    story: Mapped[str] = mapped_column(String(300), default="")
    art: Mapped[dict] = mapped_column(JSON)
    layout: Mapped[list] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(12), default="draft")
    revision: Mapped[int] = mapped_column(Integer, default=1)
    created_by: Mapped[str] = mapped_column(String(32), default="system")
    updated_by: Mapped[str] = mapped_column(String(32), default="system")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Art(BaseModel):
    floor: str
    wall: str
    crate: str
    bomb: str
    fx: str


class MapBody(BaseModel):
    """What an admin submits (docs/map-template.json)."""

    id: str = Field(pattern=r"^[a-z][a-z0-9_]{2,23}$")
    name: str = Field(min_length=2, max_length=40)
    tier: Literal["Dễ", "Trung bình", "Khó"]
    region: str = Field(default="", max_length=60)
    story: str = Field(default="", max_length=300)
    art: Art
    layout: list[str] = Field(min_length=9, max_length=17)


def corners(width: int, height: int) -> list[tuple[int, int]]:
    """Player and bot starts (practice order: top-left, then clockwise)."""
    return [(1, 1), (width - 2, 1), (width - 2, height - 2), (1, height - 2)]


def arena_spawns(width: int, height: int) -> list[tuple[int, int]]:
    """The arena's eight seats: the corners plus the middle of each edge."""
    mid_x, mid_y = (width - 1) // 2, (height - 1) // 2
    return [
        (1, 1),
        (width - 2, height - 2),
        (width - 2, 1),
        (1, height - 2),
        (mid_x, 1),
        (mid_x, height - 2),
        (1, mid_y),
        (width - 2, mid_y),
    ]


def open_cell(rows: list[str], x: int, y: int) -> bool:
    return 0 <= y < len(rows) and 0 <= x < len(rows[0]) and rows[y][x] == "."


def escapes(rows: list[str], start: tuple[int, int]) -> bool:
    """A bomb planted on ``start`` (range 2) can be outrun around a corner in <= 4 steps."""
    sx, sy = start
    queue = deque([(sx, sy, 0)])
    seen = {start}
    while queue:
        x, y, d = queue.popleft()
        if d and x != sx and y != sy:
            return True
        if d >= 4:
            continue
        for dx, dy in DIRS:
            p = (x + dx, y + dy)
            if p not in seen and open_cell(rows, *p):
                seen.add(p)
                queue.append((*p, d + 1))
    return False


def check(body: MapBody, existing: bool) -> dict:
    """Validates a map. Returns errors, warnings and the normalised layout."""
    errors: list[str] = []
    warnings: list[str] = []
    rows = [row.strip() for row in body.layout]
    if not existing and body.id in BUILTIN_IDS:
        errors.append(f"id '{body.id}' trùng bản đồ có sẵn")
    height, width = len(rows), len(rows[0]) if rows else 0
    if any(len(row) != width for row in rows):
        errors.append("Mọi hàng của layout phải dài bằng nhau")
    if not (11 <= width <= 21 and 9 <= height <= 17 and width % 2 and height % 2):
        errors.append("Kích thước phải là số lẻ: rộng 11–21 cột, cao 9–17 hàng")
    bad = sorted({ch for row in rows for ch in row} - set("#C."))
    if bad:
        errors.append(f"Ký tự không hợp lệ: {' '.join(bad)} (chỉ dùng # C .)")
    for key, value, allowed in (
        ("floor", body.art.floor, FLOORS),
        ("wall", body.art.wall, WALLS),
        ("crate", body.art.crate, CRATES),
        ("bomb", body.art.bomb, BOMBS),
        ("fx", body.art.fx, EFFECTS),
    ):
        if value not in allowed:
            errors.append(f"art.{key} '{value}' không có trong game ({', '.join(sorted(allowed))})")
    if errors:
        return {"ok": False, "errors": errors, "warnings": warnings, "layout": rows}
    if (
        rows[0] != "#" * width
        or rows[-1] != "#" * width
        or any(row[0] != "#" or row[-1] != "#" for row in rows)
    ):
        errors.append("Viền ngoài phải toàn tường #")
    starts = corners(width, height)
    for x, y in starts:
        if rows[y][x] != ".":
            errors.append(f"Ô xuất phát ({x},{y}) phải là '.'")
    for x, y in arena_spawns(width, height):
        if rows[y][x] == "#":
            errors.append(f"Ghế online ({x},{y}) không được là tường")
    if errors:
        return {"ok": False, "errors": errors, "warnings": warnings, "layout": rows}
    # Same rule as the arena: no crate within two steps of a start corner.
    grid = [list(row) for row in rows]
    cleared = 0
    for sx, sy in starts:
        for y in range(height):
            for x in range(width):
                if grid[y][x] == "C" and abs(x - sx) + abs(y - sy) <= 2:
                    grid[y][x] = "."
                    cleared += 1
    rows = ["".join(row) for row in grid]
    if cleared:
        warnings.append(f"Đã dọn {cleared} thùng sát 4 góc xuất phát (luật của server)")
    for sx, sy in starts:
        options = [(sx, sy)] + [
            (sx + dx, sy + dy) for dx, dy in DIRS if open_cell(rows, sx + dx, sy + dy)
        ]
        if not any(escapes(rows, start) for start in options):
            errors.append(f"Góc ({sx},{sy}) không có đường thoát khi đặt bom đầu tiên")
    # Corners must reach each other once crates are broken (walls never break).
    seen = {starts[0]}
    queue = deque([starts[0]])
    while queue:
        x, y = queue.popleft()
        for dx, dy in DIRS:
            p = (x + dx, y + dy)
            if p not in seen and rows[p[1]][p[0]] != "#":
                seen.add(p)
                queue.append(p)
    if any(start not in seen for start in starts):
        errors.append("Các góc xuất phát bị tường chia cắt, không gặp nhau được")
    crates = sum(row.count("C") for row in rows)
    if crates < 6:
        warnings.append(f"Ít thùng ({crates}); trận có thể kết thúc rất nhanh")
    return {"ok": not errors, "errors": errors, "warnings": warnings, "layout": rows}


def admin_view(game_map: GameMap) -> dict:
    return {
        "id": game_map.id,
        "name": game_map.name,
        "tier": game_map.tier,
        "region": game_map.region,
        "story": game_map.story,
        "art": game_map.art,
        "layout": game_map.layout,
        "columns": len(game_map.layout[0]),
        "rows": len(game_map.layout),
        "status": game_map.status,
        "revision": game_map.revision,
        "created_by": game_map.created_by,
        "updated_by": game_map.updated_by,
        "created_at": game_map.created_at,
        "updated_at": game_map.updated_at,
    }


def level_view(game_map: GameMap) -> dict:
    """Same keys as apps/practice/levels/*.json, plus revision and arena seats."""
    rows: list[str] = game_map.layout
    width, height = len(rows[0]), len(rows)
    step, rate = TIERS[game_map.tier]
    return {
        "id": game_map.id,
        "name": game_map.name.upper(),
        "subtitle": f"{game_map.tier} • {game_map.region}" if game_map.region else game_map.tier,
        "theme": game_map.art["floor"],
        "wall": game_map.art["wall"],
        "crate": game_map.art["crate"],
        "bomb": game_map.art["bomb"],
        "fx": game_map.art["fx"],
        "bot_step": step,
        "bot_bomb": rate,
        "columns": width,
        "rows": height,
        "layout": rows,
        "spawns": [list(p) for p in corners(width, height)],
        "arena_spawns": [list(p) for p in arena_spawns(width, height)],
        "story": game_map.story,
        "revision": game_map.revision,
        "custom": True,
    }


def get_map(db: Session, map_id: str) -> GameMap:
    game_map = db.get(GameMap, map_id)
    if game_map is None:
        raise HTTPException(404, "Map not found")
    return game_map


def checked(body: MapBody, existing: bool) -> list[str]:
    result = check(body, existing)
    if not result["ok"]:
        raise HTTPException(422, {"errors": result["errors"], "warnings": result["warnings"]})
    return result["layout"]


@router.get("/admin/v1/maps")
def list_maps(_: Reader, db: Db):
    rows = db.scalars(select(GameMap).order_by(GameMap.updated_at.desc()))
    return {"maps": [admin_view(m) for m in rows], "builtin": sorted(BUILTIN_IDS)}


@router.get("/admin/v1/maps/template")
def template(_: Reader):
    """The JSON an admin fills in, plus the allowed art keys."""
    return {
        "template": TEMPLATE,
        "art": {
            "floor": sorted(FLOORS),
            "wall": sorted(WALLS),
            "crate": sorted(CRATES),
            "bomb": sorted(BOMBS),
            "fx": sorted(EFFECTS),
        },
        "tiers": list(TIERS),
    }


@router.post("/admin/v1/maps/validate")
def validate(body: MapBody, db: Db, _: Reader):
    return check(body, existing=db.get(GameMap, body.id) is not None)


@router.get("/admin/v1/maps/{map_id}")
def map_detail(map_id: str, _: Reader, db: Db):
    return admin_view(get_map(db, map_id))


@router.post("/admin/v1/maps", status_code=201)
def create_map(body: MapBody, admin: Operator, db: Db):
    if db.get(GameMap, body.id):
        raise HTTPException(409, "Map id already exists")
    layout = checked(body, existing=False)
    game_map = GameMap(
        id=body.id,
        name=body.name,
        tier=body.tier,
        region=body.region,
        story=body.story,
        art=body.art.model_dump(),
        layout=layout,
        status="draft",
        revision=1,
        created_by=admin.username,
        updated_by=admin.username,
        created_at=now(),
        updated_at=now(),
    )
    db.add(game_map)
    audit(db, admin, "map.create", "map", game_map.id, after=admin_view(game_map))
    db.commit()
    return admin_view(game_map)


@router.put("/admin/v1/maps/{map_id}")
def update_map(map_id: str, body: MapBody, admin: Operator, db: Db):
    game_map = get_map(db, map_id)
    if body.id != map_id:
        raise HTTPException(422, "Map id cannot change")
    layout = checked(body, existing=True)
    before = admin_view(game_map)
    game_map.name = body.name
    game_map.tier = body.tier
    game_map.region = body.region
    game_map.story = body.story
    game_map.art = body.art.model_dump()
    game_map.layout = layout
    game_map.revision += 1
    game_map.updated_by = admin.username
    game_map.updated_at = now()
    audit(db, admin, "map.update", "map", map_id, before=before, after=admin_view(game_map))
    db.commit()
    return admin_view(game_map)


@router.post("/admin/v1/maps/{map_id}/{action}")
def map_status(map_id: str, action: Literal["publish", "hide"], admin: Operator, db: Db):
    game_map = get_map(db, map_id)
    game_map.status = "published" if action == "publish" else "hidden"
    game_map.updated_by = admin.username
    game_map.updated_at = now()
    audit(db, admin, f"map.{action}", "map", map_id)
    db.commit()
    return admin_view(game_map)


@router.get("/v1/maps")
def public_maps(
    db: Db,
    response: Response,
    if_none_match: Annotated[str | None, Header()] = None,
):
    """Published admin maps for the PC client and the arena (ETag for cheap polling)."""
    rows = [
        level_view(m)
        for m in db.scalars(
            select(GameMap).where(GameMap.status == "published").order_by(GameMap.created_at)
        )
    ]
    version = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()[:16]
    etag = f'"{version}"'
    if if_none_match == etag:
        return Response(status_code=304, headers={"ETag": etag})
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "no-cache"
    return {"version": version, "maps": rows}
