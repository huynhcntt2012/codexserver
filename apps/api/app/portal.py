"""Read-only public data for the promotion website at the site root (docs/PORTAL.md).

No sign-in, no player ids: only what any visitor may see. Events come from the
LiveOps tables, rankings from verified online matches between real players.
"""

import json
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, Query, Response
from sqlalchemy import case, exists, func, select
from sqlalchemy.orm import aliased

from app.main import Db
from app.matches import Match, Participant

router = APIRouter()

RECENT_DAYS = 30
CACHE = "public, max-age=60"


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


@router.get("/v1/public/events")
def public_events(db: Db, response: Response):
    """Published events that are live, upcoming, or ended in the last 30 days."""
    from app.admin_api import GameEvent

    at = now()
    rows = db.scalars(
        select(GameEvent)
        .where(GameEvent.status == "published")
        .where(GameEvent.end_at > at - timedelta(days=RECENT_DAYS))
        .order_by(GameEvent.start_at.desc())
    )
    events = []
    for event in rows:
        start, end = aware(event.start_at), aware(event.end_at)
        status = "upcoming" if at < start else "ended" if at > end else "live"
        config = event.config or {}
        try:
            rewards = [str(r) for r in json.loads(event.reward_items or "[]")][:6]
        except ValueError:
            rewards = []
        events.append(
            {
                "id": event.id,
                "name": event.name,
                "kind": event.kind,
                "description": event.description,
                "banner": str(config.get("banner", "")),
                "intro": str(config.get("intro", "")),
                "status": status,
                "start_at": start.isoformat(),
                "end_at": end.isoformat(),
                "rewards": rewards,
            }
        )
    order = {"live": 0, "upcoming": 1, "ended": 2}
    events.sort(key=lambda e: order[e["status"]])
    response.headers["Cache-Control"] = CACHE
    return {"server_now": at.isoformat(), "events": events}


@router.get("/v1/public/rankings")
def public_rankings(
    db: Db,
    response: Response,
    period: Literal["week", "all"] = "week",
    limit: int = Query(default=20, ge=1, le=50),
):
    """Top players by wins in verified online rounds without bots (3 pts/win, 1/KO)."""
    since = now() - timedelta(days=7) if period == "week" else None
    bot = aliased(Participant)
    has_bot = exists().where(bot.match_id == Match.id, bot.is_bot.is_(True))
    played = (
        select(
            Participant.account_id,
            func.max(Participant.name).label("name"),
            func.max(Participant.hero).label("hero"),
            func.count().label("matches"),
            func.sum(case((Participant.placement == 1, 1), else_=0)).label("wins"),
            func.sum(Participant.kills).label("kills"),
        )
        .join(Match, Match.id == Participant.match_id)
        .where(Match.verified.is_(True), Match.source == "arena", ~has_bot)
        .where(Participant.account_id.is_not(None), Participant.is_bot.is_(False))
        .group_by(Participant.account_id)
    )
    if since is not None:
        played = played.where(Match.started_at >= since)
    rows = db.execute(played).all()
    table = [
        {
            "name": r.name,
            "hero": r.hero,
            "matches": int(r.matches),
            "wins": int(r.wins or 0),
            "kills": int(r.kills or 0),
            "points": int(r.wins or 0) * 3 + int(r.kills or 0),
        }
        for r in rows
    ]
    table.sort(key=lambda r: (-r["points"], -r["wins"], r["matches"], r["name"]))
    for index, entry in enumerate(table[:limit]):
        entry["rank"] = index + 1
    response.headers["Cache-Control"] = CACHE
    return {"period": period, "updated_at": now().isoformat(), "players": table[:limit]}
