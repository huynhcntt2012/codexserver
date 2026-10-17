"""Friends, guilds and text chat. Clients poll; the server decides who may see what."""

import re
import uuid
from datetime import UTC, datetime
from typing import Annotated, Literal

import redis
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import (
    DateTime,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    and_,
    func,
    or_,
    select,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.main import Account, Base, Db, Identity, limiter

router = APIRouter(prefix="/v1")
CONTROL = re.compile(r"[\x00-\x1f\x7f]")
GUILD_NAME = re.compile(r"^[\w ]{3,24}$")
PAGE = 50


class FriendRequest(Base):
    __tablename__ = "friend_requests"
    __table_args__ = (UniqueConstraint("sender_id", "receiver_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sender_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    receiver_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(String(10), default="pending")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Guild(Base):
    __tablename__ = "guilds"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(24), unique=True)


class GuildMember(Base):
    __tablename__ = "guild_members"
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    guild_id: Mapped[str] = mapped_column(ForeignKey("guilds.id", ondelete="CASCADE"))


class ChatMessage(Base):
    __tablename__ = "chat_messages"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    channel: Mapped[str] = mapped_column(String(10))
    guild_id: Mapped[str | None] = mapped_column(ForeignKey("guilds.id", ondelete="CASCADE"))
    sender_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    recipient_id: Mapped[str | None] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    body: Mapped[str] = mapped_column(String(200))
    # Room chat: the game room key ("practice:<id>" or "arena:<process>:<id>").
    room_key: Mapped[str | None] = mapped_column(String(80))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class RoomMember(Base):
    """Who may read and write a room's chat: the creator and every player who joined."""

    __tablename__ = "game_room_members"
    room_key: Mapped[str] = mapped_column(String(80), primary_key=True)
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )


def add_member(db: Session, room_key: str, account_id: str) -> None:
    if db.get(RoomMember, (room_key, account_id)) is None:
        db.add(RoomMember(room_key=room_key, account_id=account_id))


def room_member(db: Session, room_key: str | None, account: Account) -> str:
    if not room_key or db.get(RoomMember, (room_key, account.id)) is None:
        raise HTTPException(403, "Not in this room")
    return room_key


def registered(account: Identity):
    if account.username is None:
        raise HTTPException(403, "Register an account to use friends and chat")
    return account


Member = Annotated[Account, Depends(registered)]


def check_chat_rate(account: Member):
    # Five messages per ten seconds per account; fails closed like login.
    script = """
    local count = redis.call('INCR', KEYS[1])
    if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
    return count
    """
    try:
        sent = limiter.eval(script, 1, f"chat:{account.id}", 10)
    except redis.RedisError as exc:
        raise HTTPException(503, "Chat temporarily unavailable") from exc
    if sent > 5:
        raise HTTPException(429, "Sending too fast", headers={"Retry-After": "10"})


def guild_of(db: Session, account_id: str) -> Guild | None:
    return db.scalar(select(Guild).join(GuildMember).where(GuildMember.account_id == account_id))


def link(db: Session, me: str, other: str) -> FriendRequest | None:
    return db.scalar(
        select(FriendRequest).where(
            or_(
                and_(FriendRequest.sender_id == me, FriendRequest.receiver_id == other),
                and_(FriendRequest.sender_id == other, FriendRequest.receiver_id == me),
            )
        )
    )


def relation(row: FriendRequest | None, me: str) -> str:
    if row is None:
        return "none"
    if row.status == "accepted":
        return "friend"
    return "outgoing" if row.sender_id == me else "incoming"


def profile(db: Session, account: Account, me: str) -> dict:
    guild = guild_of(db, account.id)
    return {
        "id": account.id,
        "name": account.display_name,
        "guest": account.username is None,
        "guild": guild.name if guild else None,
        "relation": relation(link(db, me, account.id), me),
    }


def target(db: Session, account_id: str, me: Account) -> Account:
    other = db.get(Account, account_id)
    if other is None or other.username is None:
        raise HTTPException(404, "Player not found")
    if other.id == me.id:
        raise HTTPException(400, "That is your own account")
    return other


@router.get("/users")
def search_users(me: Member, db: Db, q: Annotated[str, Query(min_length=2, max_length=24)]):
    cleaned = q.strip().lower().replace("\\", "").replace("%", "")
    if len(cleaned) < 2:
        return {"users": []}
    pattern = cleaned.replace("_", "\\_") + "%"
    found = db.scalars(
        select(Account)
        .where(Account.username.like(pattern, escape="\\"), Account.id != me.id)
        .order_by(Account.username)
        .limit(20)
    )
    return {"users": [profile(db, account, me.id) for account in found]}


@router.get("/users/{account_id}")
def user(account_id: str, me: Member, db: Db):
    other = db.get(Account, account_id)
    if other is None or other.username is None:
        raise HTTPException(404, "Player not found")
    return profile(db, other, me.id)


@router.get("/friends")
def friends(me: Member, db: Db):
    rows = db.scalars(
        select(FriendRequest).where(
            or_(FriendRequest.sender_id == me.id, FriendRequest.receiver_id == me.id)
        )
    )
    out: dict[str, list] = {"friends": [], "incoming": [], "outgoing": []}
    for row in rows:
        other = db.get(Account, row.receiver_id if row.sender_id == me.id else row.sender_id)
        kind = relation(row, me.id)
        entry = profile(db, other, me.id)
        if kind == "friend":
            out["friends"].append(entry)
        else:
            out[kind].append({"request_id": row.id, "user": entry})
    for key in out:
        out[key].sort(key=lambda item: (item.get("user", item))["name"])
    return out


class FriendBody(BaseModel):
    account_id: str = Field(min_length=1, max_length=36)


@router.post("/friends/requests", status_code=201)
def request_friend(body: FriendBody, me: Member, db: Db):
    other = target(db, body.account_id, me)
    row = link(db, me.id, other.id)
    if row is not None:
        if row.status == "pending" and row.receiver_id == me.id:
            # They already asked us: sending back counts as accepting.
            row.status = "accepted"
            db.commit()
            return {"request_id": row.id, "status": "accepted"}
        raise HTTPException(409, "Already friends or request pending")
    row = FriendRequest(
        id=str(uuid.uuid4()),
        sender_id=me.id,
        receiver_id=other.id,
        status="pending",
        created_at=datetime.now(UTC),
    )
    db.add(row)
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Already friends or request pending") from exc
    return {"request_id": row.id, "status": "pending"}


def pending(db: Session, request_id: str, me: Account) -> FriendRequest:
    row = db.get(FriendRequest, request_id)
    if row is None or row.status != "pending" or me.id not in (row.sender_id, row.receiver_id):
        raise HTTPException(404, "Request not found")
    return row


@router.post("/friends/requests/{request_id}/accept")
def accept(request_id: str, me: Member, db: Db):
    row = pending(db, request_id, me)
    if row.receiver_id != me.id:
        raise HTTPException(403, "Only the invited player can accept")
    row.status = "accepted"
    db.commit()
    return {"request_id": row.id, "status": "accepted"}


@router.post("/friends/requests/{request_id}/decline", status_code=204)
def decline(request_id: str, me: Member, db: Db):
    # Receiver declines, sender cancels; both just remove the request.
    db.delete(pending(db, request_id, me))
    db.commit()
    return Response(status_code=204)


@router.delete("/friends/{account_id}", status_code=204)
def unfriend(account_id: str, me: Member, db: Db):
    row = link(db, me.id, account_id)
    if row is None or row.status != "accepted":
        raise HTTPException(404, "Not friends")
    db.delete(row)
    db.commit()
    return Response(status_code=204)


def guild_view(db: Session, guild: Guild | None):
    if guild is None:
        return {"guild": None}
    count = db.scalar(select(func.count()).where(GuildMember.guild_id == guild.id))
    return {"guild": {"id": guild.id, "name": guild.name, "members": count}}


@router.get("/guild")
def my_guild(me: Member, db: Db):
    return guild_view(db, guild_of(db, me.id))


class GuildBody(BaseModel):
    name: str

    @field_validator("name")
    @classmethod
    def clean(cls, value: str) -> str:
        value = " ".join(value.split())
        if not GUILD_NAME.match(value):
            raise ValueError("3-24 letters, digits, spaces or _")
        return value


@router.post("/guild", status_code=201)
def join_guild(body: GuildBody, me: Member, db: Db):
    """Joins the guild with this name, creating it when nobody uses the name yet."""
    if guild_of(db, me.id) is not None:
        raise HTTPException(409, "Leave your current guild first")
    guild = db.scalar(select(Guild).where(func.lower(Guild.name) == body.name.lower()))
    if guild is None:
        guild = Guild(id=str(uuid.uuid4()), name=body.name)
        db.add(guild)
        db.flush()
    db.add(GuildMember(account_id=me.id, guild_id=guild.id))
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Guild name taken, try again") from exc
    return guild_view(db, guild)


@router.delete("/guild", status_code=204)
def leave_guild(me: Member, db: Db):
    member = db.get(GuildMember, me.id)
    if member is None:
        raise HTTPException(404, "Not in a guild")
    db.delete(member)
    db.commit()
    return Response(status_code=204)


class ChatBody(BaseModel):
    channel: Literal["world", "guild", "private", "room"]
    body: str = Field(min_length=1, max_length=200)
    to: str | None = Field(default=None, max_length=36)
    room: str | None = Field(default=None, max_length=80)

    @field_validator("body")
    @classmethod
    def clean(cls, value: str) -> str:
        value = CONTROL.sub(" ", value).strip()
        if not value:
            raise ValueError("Message is empty")
        return value


def view(db: Session, message: ChatMessage, me: str) -> dict:
    sender = db.get(Account, message.sender_id)
    recipient = db.get(Account, message.recipient_id) if message.recipient_id else None
    stamp = message.created_at
    if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=UTC)
    return {
        "id": message.id,
        "channel": message.channel,
        "sender": {"id": sender.id, "name": sender.display_name},
        "to": {"id": recipient.id, "name": recipient.display_name} if recipient else None,
        "body": message.body,
        "mine": message.sender_id == me,
        "created_at": stamp.isoformat(),
    }


@router.post("/chat", status_code=201, dependencies=[Depends(check_chat_rate)])
def send(body: ChatBody, me: Member, db: Db):
    message = ChatMessage(
        channel=body.channel, sender_id=me.id, body=body.body, created_at=datetime.now(UTC)
    )
    if body.channel == "guild":
        guild = guild_of(db, me.id)
        if guild is None:
            raise HTTPException(409, "Join a guild first")
        message.guild_id = guild.id
    elif body.channel == "private":
        other = target(db, body.to or "", me)
        if relation(link(db, me.id, other.id), me.id) != "friend":
            raise HTTPException(403, "Private messages are for friends only")
        message.recipient_id = other.id
    elif body.channel == "room":
        message.room_key = room_member(db, body.room, me)
    db.add(message)
    db.commit()
    return view(db, message, me.id)


@router.get("/chat")
def history(
    me: Member,
    db: Db,
    channel: Literal["all", "world", "guild", "private", "room"] = "all",
    after: Annotated[int, Query(ge=0)] = 0,
    with_id: Annotated[str | None, Query(alias="with", max_length=36)] = None,
    room: Annotated[str | None, Query(max_length=80)] = None,
):
    guild = guild_of(db, me.id)
    mine = or_(ChatMessage.sender_id == me.id, ChatMessage.recipient_id == me.id)
    seen = {
        "world": ChatMessage.channel == "world",
        "guild": and_(
            ChatMessage.channel == "guild", ChatMessage.guild_id == (guild.id if guild else None)
        ),
        "private": and_(ChatMessage.channel == "private", mine),
    }
    if channel == "room":
        # Room chat is only ever read through its own room; "all" never includes it.
        seen["room"] = and_(
            ChatMessage.channel == "room", ChatMessage.room_key == room_member(db, room, me)
        )
    rule = or_(*(v for k, v in seen.items() if k != "room")) if channel == "all" else seen[channel]
    if channel == "private" and with_id:
        rule = and_(
            rule, or_(ChatMessage.sender_id == with_id, ChatMessage.recipient_id == with_id)
        )
    newest = db.scalars(
        select(ChatMessage)
        .where(rule, ChatMessage.id > after)
        .order_by(ChatMessage.id.desc())
        .limit(PAGE)
    )
    return {"messages": [view(db, message, me.id) for message in reversed(list(newest))]}
