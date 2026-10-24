"""Room invites between friends (docs/INVITES.md).

A player seated in a waiting online room (the arena reported them, so they are a
game_room_members row) invites an accepted friend. The friend's client polls
GET /v1/invites and joins the room by id; the arena still checks seats and phase.
Invites expire after two minutes and never carry anything the server trusts later.
"""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import DateTime, ForeignKey, Integer, String, func, select
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.main import ONLINE_WINDOW, Account, Base, Db
from app.social import Member, RoomMember, link, relation

router = APIRouter(prefix="/v1")
TTL = timedelta(minutes=2)
PER_MINUTE = 10


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime | None) -> datetime | None:
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


class GameInvite(Base):
    __tablename__ = "game_invites"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    receiver_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    room_key: Mapped[str] = mapped_column(String(80))
    room_id: Mapped[str] = mapped_column(String(64))
    map_id: Mapped[str] = mapped_column(String(24), default="")
    map_name: Mapped[str] = mapped_column(String(40), default="")
    number: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(10), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def is_online(account: Account) -> bool:
    seen = aware(account.last_seen_at)
    return bool(seen and seen > now() - ONLINE_WINDOW)


def open_room(db: Session, room_key: str):
    """The arena room behind a room key, if it can still take a player."""
    from app.matches import GameRoom, room_view

    room = db.get(GameRoom, room_key)
    if room is None or room.source != "arena":
        return None
    view = room_view(room)
    if view["status"] != "waiting" or room.players >= room.max_players:
        return None
    return room


def view(db: Session, invite: GameInvite) -> dict:
    sender = db.get(Account, invite.sender_id)
    from app.matches import GameRoom

    room = db.get(GameRoom, invite.room_key)
    return {
        "id": invite.id,
        "from": {"id": invite.sender_id, "name": sender.display_name if sender else "?"},
        "room_id": invite.room_id,
        "room_key": invite.room_key,
        "map_id": invite.map_id,
        "map_name": invite.map_name,
        "number": invite.number,
        "players": room.players if room else 0,
        "max_players": room.max_players if room else 8,
        "status": invite.status,
        "expires_at": invite.expires_at,
    }


class InviteBody(BaseModel):
    account_id: str = Field(min_length=1, max_length=36)
    room_key: str = Field(min_length=1, max_length=80)
    # Shown on the card only (the server never trusts it).
    number: int = Field(default=0, ge=0, le=999)


@router.post("/invites", status_code=201)
def send_invite(body: InviteBody, me: Member, db: Db):
    friend = db.get(Account, body.account_id)
    if friend is None or relation(link(db, me.id, friend.id), me.id) != "friend":
        raise HTTPException(403, "Invites are for friends only")
    if db.get(RoomMember, (body.room_key, me.id)) is None:
        raise HTTPException(403, "Not in this room")
    room = open_room(db, body.room_key)
    if room is None:
        raise HTTPException(409, "Room is not open")
    recent = db.scalar(
        select(func.count())
        .select_from(GameInvite)
        .where(GameInvite.sender_id == me.id, GameInvite.created_at >= now() - timedelta(minutes=1))
    )
    if recent >= PER_MINUTE:
        raise HTTPException(429, "Too many invites")
    # One live invite per friend and room: re-inviting refreshes it.
    for old in db.scalars(
        select(GameInvite).where(
            GameInvite.sender_id == me.id,
            GameInvite.receiver_id == friend.id,
            GameInvite.room_key == body.room_key,
            GameInvite.status == "pending",
        )
    ):
        old.status = "replaced"
    invite = GameInvite(
        id=str(uuid.uuid4()),
        sender_id=me.id,
        receiver_id=friend.id,
        room_key=room.id,
        room_id=room.room_id,
        map_id=room.map_id or "",
        map_name=room.map_name,
        number=body.number,
        status="pending",
        created_at=now(),
        expires_at=now() + TTL,
    )
    db.add(invite)
    db.commit()
    return {**view(db, invite), "friend_online": is_online(friend)}


@router.get("/invites")
def my_invites(me: Member, db: Db):
    """Pending invites to me that have not expired, newest first."""
    rows = db.scalars(
        select(GameInvite)
        .where(
            GameInvite.receiver_id == me.id,
            GameInvite.status == "pending",
            GameInvite.expires_at > now(),
        )
        .order_by(GameInvite.created_at.desc())
        .limit(5)
    )
    return {"server_now": now(), "invites": [view(db, i) for i in rows]}


@router.post("/invites/{invite_id}/{action}")
def answer(invite_id: str, action: Literal["accept", "decline"], me: Member, db: Db):
    invite = db.get(GameInvite, invite_id)
    if invite is None or invite.receiver_id != me.id:
        raise HTTPException(404, "Invite not found")
    if invite.status != "pending" or aware(invite.expires_at) <= now():
        raise HTTPException(409, "Invite expired")
    if action == "decline":
        invite.status = "declined"
        db.commit()
        return view(db, invite)
    if open_room(db, invite.room_key) is None:
        invite.status = "expired"
        db.commit()
        raise HTTPException(409, "Room is not open")
    invite.status = "accepted"
    db.commit()
    return view(db, invite)
