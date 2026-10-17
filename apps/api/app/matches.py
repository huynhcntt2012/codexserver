"""Rooms and match history.

Two sources, kept apart so nobody mistakes one for the other:
- ``arena``: Colyseus posts room/round events with a signed service token. Trusted.
- ``practice``: the PC app reports its offline bot matches. Client-reported, so it is
  stored as unverified telemetry and never grants rewards.
"""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal

import jwt
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    func,
    select,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import Reader
from app.main import JWT_SECRET, Account, Base, Db, Identity
from app.social import add_member

router = APIRouter()
bearer = HTTPBearer(auto_error=False)
STALE_ROOM = timedelta(minutes=30)


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime | None) -> datetime | None:
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


class GameRoom(Base):
    __tablename__ = "game_rooms"
    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    source: Mapped[str] = mapped_column(String(10))
    room_id: Mapped[str] = mapped_column(String(64))
    creator_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id", ondelete="SET NULL"))
    creator_name: Mapped[str] = mapped_column(String(24), default="")
    status: Mapped[str] = mapped_column(String(10), default="waiting")
    map_name: Mapped[str] = mapped_column(String(40), default="")
    map_id: Mapped[str] = mapped_column(String(24), default="")
    players: Mapped[int] = mapped_column(Integer, default=0)
    max_players: Mapped[int] = mapped_column(Integer, default=8)
    rounds: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    closed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Match(Base):
    __tablename__ = "matches"
    __table_args__ = (UniqueConstraint("room_key", "round"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    room_key: Mapped[str] = mapped_column(String(80))
    source: Mapped[str] = mapped_column(String(10))
    round: Mapped[int] = mapped_column(Integer)
    map_name: Mapped[str] = mapped_column(String(40), default="")
    map_id: Mapped[str] = mapped_column(String(24), default="")
    verified: Mapped[bool] = mapped_column(Boolean, default=False)
    winner_name: Mapped[str | None] = mapped_column(String(24))
    duration_ms: Mapped[int] = mapped_column(Integer, default=0)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    ended_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Participant(Base):
    __tablename__ = "match_participants"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    match_id: Mapped[str] = mapped_column(ForeignKey("matches.id", ondelete="CASCADE"))
    account_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id", ondelete="SET NULL"))
    name: Mapped[str] = mapped_column(String(24))
    is_bot: Mapped[bool] = mapped_column(Boolean, default=False)
    hero: Mapped[str] = mapped_column(String(24), default="")
    placement: Mapped[int] = mapped_column(Integer)
    kills: Mapped[int] = mapped_column(Integer, default=0)
    bombs: Mapped[int] = mapped_column(Integer, default=0)
    items: Mapped[int] = mapped_column(Integer, default=0)
    score: Mapped[int] = mapped_column(Integer, default=0)
    survived_ms: Mapped[int] = mapped_column(Integer, default=0)
    winner: Mapped[bool] = mapped_column(Boolean, default=False)


def room_view(room: GameRoom) -> dict:
    status = room.status
    # Arena crashes or tunnels can drop the close event; very old open rooms read as closed.
    if status != "closed" and aware(room.updated_at) < now() - STALE_ROOM:
        status = "stale"
    return {
        "id": room.id,
        "source": room.source,
        "room_id": room.room_id,
        "creator_id": room.creator_id,
        "creator_name": room.creator_name,
        "status": status,
        "map_name": room.map_name,
        "players": room.players,
        "max_players": room.max_players,
        "rounds": room.rounds,
        "created_at": room.created_at,
        "updated_at": room.updated_at,
        "closed_at": room.closed_at,
    }


class ParticipantIn(BaseModel):
    account_id: str | None = Field(default=None, max_length=36)
    name: str = Field(min_length=1, max_length=24)
    is_bot: bool = False
    hero: str = Field(default="", max_length=24)
    placement: int = Field(ge=1, le=8)
    kills: int = Field(default=0, ge=0, le=99)
    bombs: int = Field(default=0, ge=0, le=999)
    items: int = Field(default=0, ge=0, le=999)
    score: int = Field(default=0, ge=0, le=1_000_000)
    survived_ms: int = Field(default=0, ge=0, le=3_600_000)
    winner: bool = False


def record_match(
    db: Session,
    room: GameRoom,
    round_no: int,
    verified: bool,
    duration_ms: int,
    participants: list[ParticipantIn],
    practice: bool = False,
) -> Match | None:
    """Idempotent on (room, round): a retried event returns the stored match."""
    existing = db.scalar(select(Match).where(Match.room_key == room.id, Match.round == round_no))
    if existing:
        return existing
    ended = now()
    match = Match(
        id=str(uuid.uuid4()),
        room_key=room.id,
        source=room.source,
        round=round_no,
        map_name=room.map_name,
        map_id=room.map_id or "",
        verified=verified,
        winner_name=next((p.name for p in participants if p.winner), None),
        duration_ms=duration_ms,
        started_at=ended - timedelta(milliseconds=duration_ms),
        ended_at=ended,
    )
    db.add(match)
    for p in participants:
        account = db.get(Account, p.account_id) if p.account_id else None
        db.add(
            Participant(
                match_id=match.id,
                account_id=account.id if account else None,
                name=p.name,
                is_bot=p.is_bot,
                hero=p.hero,
                placement=p.placement,
                kills=p.kills,
                bombs=p.bombs,
                items=p.items,
                score=p.score,
                survived_ms=p.survived_ms,
                winner=p.winner,
            )
        )
    room.rounds = max(room.rounds, round_no)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return db.scalar(select(Match).where(Match.room_key == room.id, Match.round == round_no))
    # Missions: only a newly stored match counts (retried events return above).
    from app.liveops import on_match

    on_match(db, match, participants, room.source, practice)
    return match


# ---------------------------------------------------------------- Arena ingestion


def arena_service(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
) -> None:
    if credentials is None:
        raise HTTPException(401, "Service token required")
    try:
        jwt.decode(
            credentials.credentials,
            JWT_SECRET,
            algorithms=["HS256"],
            audience="suni-ingest",
            issuer="suni-arena",
            options={"require": ["exp", "iat"]},
        )
    except jwt.InvalidTokenError as exc:
        raise HTTPException(401, "Invalid service token") from exc


class ArenaPlayer(BaseModel):
    account_id: str = Field(max_length=36)
    name: str = Field(max_length=24)


class ArenaEvent(BaseModel):
    type: Literal["room", "closed", "match"]
    room_id: str = Field(min_length=1, max_length=64)
    process_id: str = Field(default="", max_length=64)
    phase: str = Field(default="waiting", max_length=12)
    players: list[ArenaPlayer] = Field(default_factory=list, max_length=8)
    max_players: int = Field(default=8, ge=1, le=8)
    # Protocol v2 rooms pick one of the shared maps; v1 rooms omit it.
    map_name: str = Field(default="Neon Garden", min_length=1, max_length=40)
    map_id: str = Field(default="", max_length=24, pattern=r"^[a-z0-9_]*$")
    round: int = Field(default=0, ge=0)
    duration_ms: int = Field(default=0, ge=0, le=3_600_000)
    # Practice room with server bots: verified, but counts as practice for missions.
    practice: bool = False
    results: list[ParticipantIn] = Field(default_factory=list, max_length=8)


def arena_room(db: Session, event: ArenaEvent) -> GameRoom:
    key = f"arena:{event.process_id}:{event.room_id}"[:80]
    room = db.get(GameRoom, key)
    if room is None:
        room = GameRoom(
            id=key,
            source="arena",
            room_id=event.room_id,
            status="waiting",
            map_name=event.map_name,
            map_id=event.map_id,
            max_players=event.max_players,
            created_at=now(),
            updated_at=now(),
        )
        db.add(room)
    return room


@router.post("/internal/v1/arena/events", status_code=204, dependencies=[Depends(arena_service)])
def arena_event(event: ArenaEvent, db: Db):
    room = arena_room(db, event)
    room.updated_at = now()
    if event.type == "closed":
        room.status = "closed"
        room.closed_at = now()
    elif event.type == "room":
        room.status = "waiting" if event.phase == "waiting" else "playing"
        room.players = len(event.players)
        room.map_name = event.map_name
        room.map_id = event.map_id
        for player in event.players:
            if db.get(Account, player.account_id):
                add_member(db, room.id, player.account_id)
        if room.creator_id is None and event.players:
            first = db.get(Account, event.players[0].account_id)
            if first:
                room.creator_id = first.id
                room.creator_name = first.display_name
    else:
        room.status = "playing" if event.players else room.status
        if event.map_id:
            room.map_name, room.map_id = event.map_name, event.map_id
        record_match(db, room, event.round, True, event.duration_ms, event.results, event.practice)
    db.commit()


# ---------------------------------------------------------------- Practice reports


class PracticeRoom(BaseModel):
    map_name: str = Field(default="", max_length=40)
    map_id: str = Field(default="", max_length=24, pattern=r"^[a-z0-9_]*$")


@router.post("/v1/practice/rooms", status_code=201)
def practice_room(body: PracticeRoom, account: Identity, db: Db):
    room_id = uuid.uuid4().hex[:12]
    room = GameRoom(
        id=f"practice:{room_id}",
        source="practice",
        room_id=room_id,
        creator_id=account.id,
        creator_name=account.display_name,
        status="waiting",
        map_name=body.map_name,
        map_id=body.map_id,
        players=4,
        max_players=4,
        created_at=now(),
        updated_at=now(),
    )
    db.add(room)
    add_member(db, room.id, account.id)
    db.commit()
    return {"room_id": room_id, "room_key": room.id}


def own_room(db: Session, room_id: str, account: Account) -> GameRoom:
    room = db.get(GameRoom, f"practice:{room_id}")
    if room is None or room.creator_id != account.id:
        raise HTTPException(404, "Room not found")
    return room


class PracticeState(BaseModel):
    status: Literal["waiting", "playing", "closed"]
    map_name: str | None = Field(default=None, max_length=40)
    map_id: str | None = Field(default=None, max_length=24, pattern=r"^[a-z0-9_]*$")


@router.post("/v1/practice/rooms/{room_id}/state", status_code=204)
def practice_state(room_id: str, body: PracticeState, account: Identity, db: Db):
    room = own_room(db, room_id, account)
    room.status = body.status
    if body.map_name is not None:
        room.map_name = body.map_name
    if body.map_id is not None:
        room.map_id = body.map_id
    room.updated_at = now()
    if body.status == "closed":
        room.closed_at = now()
    db.commit()


class PracticeResult(BaseModel):
    round: int = Field(ge=1, le=10_000)
    duration_ms: int = Field(ge=0, le=3_600_000)
    participants: list[ParticipantIn] = Field(min_length=1, max_length=8)


@router.post("/v1/practice/rooms/{room_id}/matches", status_code=201)
def practice_match(room_id: str, body: PracticeResult, account: Identity, db: Db):
    room = own_room(db, room_id, account)
    # The reporting player is the only human; never trust account ids from the client.
    people = [p for p in body.participants if not p.is_bot]
    if len(people) != 1:
        raise HTTPException(422, "Exactly one human player")
    people[0].account_id = account.id
    for p in body.participants:
        if p.is_bot:
            p.account_id = None
    room.updated_at = now()
    match = record_match(db, room, body.round, False, body.duration_ms, body.participants)
    db.commit()
    return {"match_id": match.id if match else None}


@router.get("/v1/rooms/summary")
def rooms_summary(db: Db):
    """Public counts for lobby lists: people in open rooms per map (no identities)."""
    maps: dict[str, dict] = {}
    for room in db.scalars(select(GameRoom).where(GameRoom.status != "closed")):
        view = room_view(room)
        if view["status"] not in ("waiting", "playing"):
            continue
        entry = maps.setdefault(
            room.map_name.casefold(),
            {"name": room.map_name, "players": 0, "waiting": 0, "playing": 0},
        )
        # Practice rooms hold one person (the rest are bots).
        entry["players"] += 1 if room.source == "practice" else room.players
        entry[view["status"]] += 1
    return {
        "maps": list(maps.values()),
        "players": sum(m["players"] for m in maps.values()),
        "rooms": sum(m["waiting"] + m["playing"] for m in maps.values()),
    }


# ---------------------------------------------------------------- Admin views


def counts_by_status(db: Session) -> dict:
    rooms = [room_view(r) for r in db.scalars(select(GameRoom))]
    out = {"waiting": 0, "playing": 0, "closed": 0, "stale": 0}
    for r in rooms:
        out[r["status"]] = out.get(r["status"], 0) + 1
    return {"total": len(rooms), **out}


@router.get("/admin/v1/rooms")
def admin_rooms(
    _: Reader,
    db: Db,
    status: str = "",
    source: str = "",
    creator: str = "",
    page: Annotated[int, Query(ge=1)] = 1,
    size: Annotated[int, Query(ge=1, le=100)] = 25,
):
    query = select(GameRoom).order_by(GameRoom.created_at.desc())
    if source:
        query = query.where(GameRoom.source == source)
    if creator:
        query = query.where(GameRoom.creator_id == creator)
    rows = [room_view(r) for r in db.scalars(query)]
    if status:
        rows = [r for r in rows if r["status"] == status]
    creators = db.execute(
        select(GameRoom.creator_id, GameRoom.creator_name, func.count())
        .where(GameRoom.creator_id.is_not(None))
        .group_by(GameRoom.creator_id, GameRoom.creator_name)
        .order_by(func.count().desc())
        .limit(10)
    ).all()
    return {
        "summary": counts_by_status(db),
        "top_creators": [{"account_id": a, "name": n, "rooms": c} for a, n, c in creators],
        "items": rows[(page - 1) * size : page * size],
        "total": len(rows),
        "page": page,
        "size": size,
    }


def participant_view(p: Participant) -> dict:
    return {
        "account_id": p.account_id,
        "name": p.name,
        "is_bot": p.is_bot,
        "hero": p.hero,
        "placement": p.placement,
        "kills": p.kills,
        "bombs": p.bombs,
        "items": p.items,
        "score": p.score,
        "survived_ms": p.survived_ms,
        "winner": p.winner,
    }


def match_view(db: Session, match: Match, with_players: bool = True) -> dict:
    players = db.scalars(
        select(Participant).where(Participant.match_id == match.id).order_by(Participant.placement)
    )
    room = db.get(GameRoom, match.room_key)
    view = {
        "id": match.id,
        "room_key": match.room_key,
        "room_id": room.room_id if room else match.room_key,
        "creator_name": room.creator_name if room else "",
        "source": match.source,
        "round": match.round,
        "map_name": match.map_name,
        "verified": match.verified,
        "winner_name": match.winner_name,
        "duration_ms": match.duration_ms,
        "started_at": match.started_at,
        "ended_at": match.ended_at,
    }
    if with_players:
        view["participants"] = [participant_view(p) for p in players]
    return view


@router.get("/admin/v1/matches")
def admin_matches(
    _: Reader,
    db: Db,
    source: str = "",
    account_id: str = "",
    page: Annotated[int, Query(ge=1)] = 1,
    size: Annotated[int, Query(ge=1, le=100)] = 20,
):
    query = select(Match)
    if source:
        query = query.where(Match.source == source)
    if account_id:
        query = query.where(
            Match.id.in_(select(Participant.match_id).where(Participant.account_id == account_id))
        )
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    rows = db.scalars(query.order_by(Match.ended_at.desc()).offset((page - 1) * size).limit(size))
    return {
        "items": [match_view(db, m) for m in rows],
        "total": total,
        "page": page,
        "size": size,
    }


def player_stats(db: Session, account_id: str) -> dict:
    rows = list(db.scalars(select(Participant).where(Participant.account_id == account_id)))
    return {
        "matches": len(rows),
        "wins": sum(1 for p in rows if p.winner),
        "kills": sum(p.kills for p in rows),
        "rooms_created": db.scalar(
            select(func.count()).select_from(GameRoom).where(GameRoom.creator_id == account_id)
        ),
    }


def recent_counts(db: Session, since: datetime) -> dict:
    return {
        "matches": db.scalar(
            select(func.count()).select_from(Match).where(Match.ended_at >= since)
        ),
        "rooms": db.scalar(
            select(func.count()).select_from(GameRoom).where(GameRoom.created_at >= since)
        ),
    }
