"""Leaderboards: experience, skin points and gold (docs/LEADERBOARD.md).

Every value comes from server data, never from the client:
- exp: verified arena rounds (online rooms and arena-hosted practice) and boss
  raids, scored by the weights in the settings;
- skin: cosmetics owned (item_catalog categories in SKIN_CATEGORIES), points by rarity;
- gold: the wallet balance.
Admins tune the weights, hide a player from every board (with a reason, audited)
and see account ids; players only see names, heroes, values and ranks.
Settings live in site_settings under the key "leaderboard".
"""

from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import case, func, select
from sqlalchemy.orm import Session

from app.admin_api import ItemCatalog
from app.admin_auth import Operator, Reader, audit
from app.boss import BossRaidMatch, BossRaidParticipant
from app.economy import Wallet
from app.main import Account, Db, Identity, InventoryItem
from app.matches import Match, Participant
from app.website import SiteSetting

router = APIRouter()

Board = Literal["exp", "skin", "gold"]
BOARDS: tuple[str, ...] = ("exp", "skin", "gold")
SKIN_CATEGORIES = ("outfit", "hat", "wings", "pet", "bomb_skin", "effect", "accessory")
SETTING_KEY = "leaderboard"
MAX_ROWS = 100
DEFAULT_HERO = "bombo"

DEFAULTS: dict = {
    "exp": {"match": 20, "win": 50, "kill": 10, "boss_raid": 30, "boss_win": 60},
    "skin": {"common": 10, "rare": 30, "epic": 60, "legendary": 100},
    "size": 50,
    "hidden": {},  # account_id -> {"reason", "by", "at"}
}


def now() -> datetime:
    return datetime.now(UTC)


# ---------------------------------------------------------------- settings


class ExpWeights(BaseModel):
    match: int = Field(ge=0, le=10_000)
    win: int = Field(ge=0, le=10_000)
    kill: int = Field(ge=0, le=10_000)
    boss_raid: int = Field(ge=0, le=10_000)
    boss_win: int = Field(ge=0, le=10_000)


class SkinPoints(BaseModel):
    common: int = Field(ge=0, le=100_000)
    rare: int = Field(ge=0, le=100_000)
    epic: int = Field(ge=0, le=100_000)
    legendary: int = Field(ge=0, le=100_000)


class LeaderboardSettings(BaseModel):
    exp: ExpWeights
    skin: SkinPoints
    size: int = Field(ge=5, le=MAX_ROWS)


class HideBody(BaseModel):
    reason: str = Field(min_length=3, max_length=300)


def settings(db: Session) -> tuple[dict, SiteSetting | None]:
    """Stored settings merged over DEFAULTS (unknown keys dropped)."""
    row = db.get(SiteSetting, SETTING_KEY)
    stored = dict(row.value) if row and isinstance(row.value, dict) else {}
    value = {
        "exp": {**DEFAULTS["exp"], **dict(stored.get("exp") or {})},
        "skin": {**DEFAULTS["skin"], **dict(stored.get("skin") or {})},
        "size": int(stored.get("size") or DEFAULTS["size"]),
        "hidden": dict(stored.get("hidden") or {}),
    }
    return value, row


def save(db: Session, value: dict, row: SiteSetting | None, by: str) -> None:
    if row is None:
        row = SiteSetting(key=SETTING_KEY, value={}, updated_at=now())
        db.add(row)
    row.value = value
    row.updated_by = by
    row.updated_at = now()


# ---------------------------------------------------------------- scores


def exp_scores(db: Session, weights: dict) -> dict[str, int]:
    rounds = db.execute(
        select(
            Participant.account_id,
            func.count().label("matches"),
            func.sum(case((Participant.placement == 1, 1), else_=0)).label("wins"),
            func.coalesce(func.sum(Participant.kills), 0).label("kills"),
        )
        .join(Match, Match.id == Participant.match_id)
        .where(Match.verified.is_(True), Match.source == "arena")
        .where(Participant.account_id.is_not(None), Participant.is_bot.is_(False))
        .group_by(Participant.account_id)
    ).all()
    scores: dict[str, int] = {}
    for r in rounds:
        scores[r.account_id] = (
            int(r.matches) * weights["match"]
            + int(r.wins or 0) * weights["win"]
            + int(r.kills or 0) * weights["kill"]
        )
    raids = db.execute(
        select(
            BossRaidParticipant.account_id,
            func.count().label("raids"),
            func.sum(case((BossRaidMatch.result == "WIN", 1), else_=0)).label("wins"),
        )
        .join(BossRaidMatch, BossRaidMatch.id == BossRaidParticipant.match_id)
        .group_by(BossRaidParticipant.account_id)
    ).all()
    for r in raids:
        scores[r.account_id] = scores.get(r.account_id, 0) + (
            int(r.raids) * weights["boss_raid"] + int(r.wins or 0) * weights["boss_win"]
        )
    return scores


def skin_scores(db: Session, points: dict) -> dict[str, int]:
    rows = db.execute(
        select(InventoryItem.account_id, ItemCatalog.rarity, func.count().label("owned"))
        .join(ItemCatalog, ItemCatalog.id == InventoryItem.item_id)
        .where(ItemCatalog.category.in_(SKIN_CATEGORIES))
        .group_by(InventoryItem.account_id, ItemCatalog.rarity)
    ).all()
    scores: dict[str, int] = {}
    for r in rows:
        scores[r.account_id] = scores.get(r.account_id, 0) + int(r.owned) * int(
            points.get(r.rarity, 0)
        )
    return scores


def gold_scores(db: Session) -> dict[str, int]:
    return {w.account_id: int(w.gold) for w in db.scalars(select(Wallet).where(Wallet.gold > 0))}


def scores(db: Session, board: str, config: dict) -> dict[str, int]:
    if board == "exp":
        return exp_scores(db, config["exp"])
    if board == "skin":
        return skin_scores(db, config["skin"])
    return gold_scores(db)


def heroes(db: Session, ids: list[str]) -> dict[str, str]:
    """Each player's hero in their latest recorded round (portrait on the board)."""
    if not ids:
        return {}
    latest = (
        select(Participant.account_id, func.max(Match.ended_at).label("at"))
        .join(Match, Match.id == Participant.match_id)
        .where(Participant.account_id.in_(ids), Participant.hero != "")
        .group_by(Participant.account_id)
        .subquery()
    )
    rows = db.execute(
        select(Participant.account_id, Participant.hero)
        .join(Match, Match.id == Participant.match_id)
        .join(
            latest,
            (latest.c.account_id == Participant.account_id) & (latest.c.at == Match.ended_at),
        )
    ).all()
    return {r.account_id: r.hero for r in rows}


def ranked(db: Session, board: str, config: dict, include_hidden: bool = False) -> list[dict]:
    """Every player with a score above 0, best first; ties by name then id."""
    values = scores(db, board, config)
    hidden = config["hidden"]
    ids = [a for a, v in values.items() if v > 0 and (include_hidden or a not in hidden)]
    names = (
        {a.id: a.display_name for a in db.scalars(select(Account).where(Account.id.in_(ids)))}
        if ids
        else {}
    )
    rows = [
        {"account_id": a, "name": names.get(a, "?"), "value": values[a]} for a in ids if a in names
    ]
    rows.sort(key=lambda r: (-r["value"], r["name"].lower(), r["account_id"]))
    rank = 0
    for row in rows:
        if include_hidden and row["account_id"] in hidden:
            row["rank"] = None
            continue
        rank += 1
        row["rank"] = rank
    return rows


def public_row(row: dict, hero: str) -> dict:
    return {"rank": row["rank"], "name": row["name"], "hero": hero, "value": row["value"]}


# ---------------------------------------------------------------- player API


@router.get("/v1/leaderboards")
def leaderboards(account: Identity, db: Db, limit: int = Query(default=10, ge=1, le=MAX_ROWS)):
    """Top players of every board and the caller's own rank (null when unranked)."""
    config, _ = settings(db)
    limit = min(limit, config["size"])
    boards: dict = {}
    me: dict = {}
    tables = {board: ranked(db, board, config) for board in BOARDS}
    top_ids = {r["account_id"] for t in tables.values() for r in t[:limit]}
    faces = heroes(db, sorted(top_ids | {account.id}))
    for board, table in tables.items():
        boards[board] = [
            public_row(r, faces.get(r["account_id"], DEFAULT_HERO)) for r in table[:limit]
        ]
        own = next((r for r in table if r["account_id"] == account.id), None)
        me[board] = {
            "rank": own["rank"] if own else None,
            "value": own["value"] if own else 0,
        }
    return {
        "updated_at": now().isoformat(),
        "boards": boards,
        "me": {
            **me,
            "name": account.display_name,
            "hero": faces.get(account.id, DEFAULT_HERO),
            "hidden": account.id in config["hidden"],
        },
    }


# ---------------------------------------------------------------- admin API


def settings_view(config: dict, row: SiteSetting | None) -> dict:
    return {
        "exp": config["exp"],
        "skin": config["skin"],
        "size": config["size"],
        "defaults": {k: DEFAULTS[k] for k in ("exp", "skin", "size")},
        "skin_categories": list(SKIN_CATEGORIES),
        "hidden_count": len(config["hidden"]),
        "updated_by": row.updated_by if row else None,
        "updated_at": row.updated_at if row else None,
    }


@router.get("/admin/v1/leaderboards")
def admin_board(
    _: Reader,
    db: Db,
    board: Board = "exp",
    q: str = Query(default="", max_length=24),
    limit: int = Query(default=50, ge=1, le=MAX_ROWS),
):
    """One board with account ids; hidden players listed (rank null) so they can be restored."""
    config, _row = settings(db)
    table = ranked(db, board, config, include_hidden=True)
    needle = q.strip().lower()
    if needle:
        table = [r for r in table if needle in r["name"].lower() or r["account_id"] == q.strip()]
    rows = table[:limit]
    faces = heroes(db, [r["account_id"] for r in rows])
    hidden = config["hidden"]
    return {
        "board": board,
        "total": len(table),
        "rows": [
            {
                **r,
                "hero": faces.get(r["account_id"], DEFAULT_HERO),
                "hidden": hidden.get(r["account_id"]),
            }
            for r in rows
        ],
    }


@router.get("/admin/v1/leaderboards/settings")
def admin_settings(_: Reader, db: Db):
    config, row = settings(db)
    return settings_view(config, row)


@router.put("/admin/v1/leaderboards/settings")
def update_settings(body: LeaderboardSettings, admin: Operator, db: Db):
    config, row = settings(db)
    before = {k: config[k] for k in ("exp", "skin", "size")}
    after = body.model_dump()
    save(db, {**config, **after}, row, admin.username)
    audit(db, admin, "leaderboard.settings", "leaderboard", SETTING_KEY, before=before, after=after)
    db.commit()
    config, row = settings(db)
    return settings_view(config, row)


@router.get("/admin/v1/leaderboards/hidden")
def hidden_players(_: Reader, db: Db):
    config, _row = settings(db)
    ids = list(config["hidden"])
    names = (
        {a.id: a.display_name for a in db.scalars(select(Account).where(Account.id.in_(ids)))}
        if ids
        else {}
    )
    return {
        "players": [
            {"account_id": a, "name": names.get(a, "?"), **config["hidden"][a]}
            for a in sorted(ids, key=lambda a: str(config["hidden"][a].get("at", "")), reverse=True)
        ]
    }


@router.post("/admin/v1/leaderboards/hidden/{account_id}")
def hide_player(account_id: str, body: HideBody, admin: Operator, db: Db):
    """Takes the player off every board (cheating, offensive name, test account...)."""
    if db.get(Account, account_id) is None:
        raise HTTPException(404, "Account not found")
    config, row = settings(db)
    entry = {"reason": body.reason, "by": admin.username, "at": now().isoformat()}
    config["hidden"] = {**config["hidden"], account_id: entry}
    save(db, config, row, admin.username)
    audit(db, admin, "leaderboard.hide", "account", account_id, body.reason)
    db.commit()
    return {"account_id": account_id, "hidden": entry}


@router.delete("/admin/v1/leaderboards/hidden/{account_id}")
def show_player(account_id: str, admin: Operator, db: Db):
    config, row = settings(db)
    if account_id not in config["hidden"]:
        raise HTTPException(404, "Player is not hidden")
    config["hidden"] = {k: v for k, v in config["hidden"].items() if k != account_id}
    save(db, config, row, admin.username)
    audit(db, admin, "leaderboard.show", "account", account_id)
    db.commit()
    return {"account_id": account_id, "hidden": None}
