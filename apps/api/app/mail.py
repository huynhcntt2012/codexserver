"""In-game mailbox (docs/MAIL.md): admins send messages to chosen players or to the
whole server, optionally with rewards (gold, gem, catalog items) claimed in game.

- A message is one row; per-player state (read, claimed, deleted) is a receipt
  row created on first touch, so a server-wide message costs one row to send.
- Server-wide messages reach every account, including ones made after sending,
  until `expires_at`. Recalling a message hides it from inboxes that have not
  claimed it yet.
- Claiming is idempotent: the receipt is marked claimed with a conditional
  UPDATE, so two devices tapping NHẬN at once grant once; wallet postings also
  carry a unique ledger reference.
"""

import uuid
from datetime import UTC, datetime, timedelta
from typing import Literal

from fastapi import APIRouter, HTTPException, Query, Response
from pydantic import BaseModel, Field
from sqlalchemy import JSON, DateTime, ForeignKey, String, Text, func, or_, select, update
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import Operator, Reader, audit
from app.economy import locked_wallet, post_ledger
from app.liveops import grant_item
from app.main import Account, Base, Db, Identity

router = APIRouter()

CATEGORIES = ("admin", "system", "event", "maintenance", "reward")
MAX_TARGETS = 200
MAX_REWARDS = 6
DEFAULT_DAYS = 30
INBOX_LIMIT = 50


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime | None) -> datetime | None:
    return value.replace(tzinfo=UTC) if value and value.tzinfo is None else value


class MailMessage(Base):
    __tablename__ = "mail_messages"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    category: Mapped[str] = mapped_column(String(16), default="admin")
    sender: Mapped[str] = mapped_column(String(40), default="Ban điều hành")
    title: Mapped[str] = mapped_column(String(80))
    body: Mapped[str] = mapped_column(Text, default="")
    rewards: Mapped[list] = mapped_column(JSON, default=list)
    audience: Mapped[str] = mapped_column(String(8), default="all")  # all | players
    targets: Mapped[list] = mapped_column(JSON, default=list)  # account ids when "players"
    status: Mapped[str] = mapped_column(String(12), default="active")  # active | recalled
    created_by: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class MailReceipt(Base):
    __tablename__ = "mail_receipts"
    message_id: Mapped[str] = mapped_column(
        ForeignKey("mail_messages.id", ondelete="CASCADE"), primary_key=True
    )
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    read_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class MailReward(BaseModel):
    type: Literal["gold", "gem", "item"]
    amount: int = Field(default=1, ge=1, le=1_000_000)
    item_id: str | None = Field(default=None, max_length=64)


class NewMail(BaseModel):
    title: str = Field(min_length=2, max_length=80)
    body: str = Field(default="", max_length=2000)
    category: Literal["admin", "system", "event", "maintenance", "reward"] = "admin"
    sender: str = Field(default="Ban điều hành", min_length=2, max_length=40)
    rewards: list[MailReward] = Field(default_factory=list, max_length=MAX_REWARDS)
    audience: Literal["all", "players"] = "all"
    targets: list[str] = Field(default_factory=list, max_length=MAX_TARGETS)
    expires_days: int = Field(default=DEFAULT_DAYS, ge=1, le=365)


class Reason(BaseModel):
    reason: str = Field(min_length=3, max_length=300)


# ---------------------------------------------------------------- helpers


def for_account(db: Session, account_id: str) -> list[MailMessage]:
    """Active, unexpired messages for this account (targets checked in Python:
    JSON containment differs between SQLite and PostgreSQL)."""
    rows = db.scalars(
        select(MailMessage)
        .where(MailMessage.status == "active", MailMessage.expires_at > now())
        .order_by(MailMessage.created_at.desc())
    ).all()
    return [m for m in rows if m.audience == "all" or account_id in (m.targets or [])]


def receipts(db: Session, account_id: str, ids: list[str]) -> dict[str, MailReceipt]:
    if not ids:
        return {}
    rows = db.scalars(
        select(MailReceipt).where(
            MailReceipt.account_id == account_id, MailReceipt.message_id.in_(ids)
        )
    )
    return {r.message_id: r for r in rows}


def receipt(db: Session, message: MailMessage, account: Account) -> MailReceipt:
    row = db.get(MailReceipt, (message.id, account.id))
    if row is None:
        row = MailReceipt(message_id=message.id, account_id=account.id)
        db.add(row)
        db.flush()
    return row


def item_names(db: Session, rewards: list[dict]) -> dict[str, tuple[str, str | None]]:
    from app.admin_api import ItemCatalog

    ids = [str(r.get("item_id")) for r in rewards if r.get("type") == "item"]
    if not ids:
        return {}
    return {
        i.id: (i.name, i.icon)
        for i in db.scalars(select(ItemCatalog).where(ItemCatalog.id.in_(ids)))
    }


def reward_views(db: Session, rewards: list[dict]) -> list[dict]:
    names = item_names(db, rewards)
    out = []
    for r in rewards:
        view = {"type": r["type"], "amount": int(r.get("amount", 1))}
        if r["type"] == "item":
            name, icon = names.get(str(r.get("item_id")), (str(r.get("item_id")), None))
            view.update(item_id=r.get("item_id"), name=name, icon=icon)
        else:
            view["name"] = "Vàng" if r["type"] == "gold" else "Kim cương"
        out.append(view)
    return out


def player_view(db: Session, message: MailMessage, row: MailReceipt | None) -> dict:
    rewards = message.rewards or []
    claimed = bool(row and row.claimed_at)
    return {
        "id": message.id,
        "category": message.category,
        "sender": message.sender,
        "title": message.title,
        "body": message.body,
        "rewards": reward_views(db, rewards),
        "has_rewards": bool(rewards),
        "read": bool(row and row.read_at),
        "claimed": claimed,
        "claimable": bool(rewards) and not claimed,
        "created_at": aware(message.created_at).isoformat(),
        "expires_at": aware(message.expires_at).isoformat(),
    }


def get_visible(db: Session, message_id: str, account: Account) -> MailMessage:
    message = db.get(MailMessage, message_id)
    if (
        message is None
        or message.status != "active"
        or aware(message.expires_at) <= now()
        or (message.audience == "players" and account.id not in (message.targets or []))
    ):
        raise HTTPException(404, "Message not found")
    row = db.get(MailReceipt, (message.id, account.id))
    if row and row.deleted_at:
        raise HTTPException(404, "Message not found")
    return message


def claim_one(db: Session, message: MailMessage, account: Account) -> bool:
    """Grants the rewards once; False when already claimed or nothing to claim."""
    if not message.rewards:
        return False
    row = receipt(db, message, account)
    marked = db.execute(
        update(MailReceipt)
        .where(
            MailReceipt.message_id == message.id,
            MailReceipt.account_id == account.id,
            MailReceipt.claimed_at.is_(None),
        )
        .values(claimed_at=now(), read_at=func.coalesce(MailReceipt.read_at, now()))
        .execution_options(synchronize_session=False)
    ).rowcount
    if not marked:
        return False
    wallet = None
    for i, reward in enumerate(message.rewards):
        if reward["type"] in ("gold", "gem"):
            wallet = wallet or locked_wallet(db, account)
            post_ledger(
                db,
                wallet,
                reward["type"],
                int(reward["amount"]),
                "mail",
                f"mail:{message.id}:{account.id}:{i}",
                note=message.title,
                actor=message.created_by,
            )
        else:
            grant_item(db, account.id, str(reward.get("item_id")), int(reward.get("amount", 1)))
    db.refresh(row)
    return True


# ---------------------------------------------------------------- player API


@router.get("/v1/mail")
def inbox(account: Identity, db: Db):
    messages = for_account(db, account.id)
    states = receipts(db, account.id, [m.id for m in messages])
    shown = [m for m in messages if not (states.get(m.id) and states[m.id].deleted_at)][
        :INBOX_LIMIT
    ]
    views = [player_view(db, m, states.get(m.id)) for m in shown]
    return {
        "server_now": now().isoformat(),
        "unread": sum(not v["read"] for v in views),
        "claimable": sum(v["claimable"] for v in views),
        "messages": views,
    }


@router.post("/v1/mail/{message_id}/read")
def read(message_id: str, account: Identity, db: Db):
    message = get_visible(db, message_id, account)
    row = receipt(db, message, account)
    row.read_at = row.read_at or now()
    db.commit()
    return player_view(db, message, row)


@router.post("/v1/mail/{message_id}/claim")
def claim(message_id: str, account: Identity, db: Db):
    message = get_visible(db, message_id, account)
    if not message.rewards:
        raise HTTPException(409, "No rewards in this message")
    if not claim_one(db, message, account):
        db.rollback()
        raise HTTPException(409, "Already claimed")
    db.commit()
    return player_view(db, message, db.get(MailReceipt, (message.id, account.id)))


@router.post("/v1/mail/read-all", status_code=204)
def read_all(account: Identity, db: Db):
    for message in for_account(db, account.id):
        row = receipt(db, message, account)
        row.read_at = row.read_at or now()
    db.commit()
    return Response(status_code=204)


@router.post("/v1/mail/claim-all")
def claim_all(account: Identity, db: Db):
    states = receipts(db, account.id, [m.id for m in for_account(db, account.id)])
    count = 0
    for message in for_account(db, account.id):
        state = states.get(message.id)
        if state and state.deleted_at:
            continue
        count += claim_one(db, message, account)
    db.commit()
    return {"claimed": count}


@router.delete("/v1/mail/{message_id}", status_code=204)
def delete(message_id: str, account: Identity, db: Db):
    """Hides it from this inbox; unclaimed rewards must be claimed first."""
    message = get_visible(db, message_id, account)
    row = receipt(db, message, account)
    if message.rewards and not row.claimed_at:
        db.rollback()
        raise HTTPException(409, "Claim the rewards first")
    row.deleted_at = now()
    db.commit()
    return Response(status_code=204)


@router.post("/v1/mail/delete-read")
def delete_read(account: Identity, db: Db):
    """Thùng rác: removes read messages with nothing left to claim."""
    count = 0
    for message in for_account(db, account.id):
        row = db.get(MailReceipt, (message.id, account.id))
        if row and row.read_at and not row.deleted_at and (not message.rewards or row.claimed_at):
            row.deleted_at = now()
            count += 1
    db.commit()
    return {"deleted": count}


# ---------------------------------------------------------------- admin API


def admin_view(db: Session, message: MailMessage) -> dict:
    stats = db.execute(
        select(
            func.count(MailReceipt.read_at),
            func.count(MailReceipt.claimed_at),
        ).where(MailReceipt.message_id == message.id)
    ).one()
    phase = message.status
    if phase == "active" and aware(message.expires_at) <= now():
        phase = "expired"
    return {
        "id": message.id,
        "category": message.category,
        "sender": message.sender,
        "title": message.title,
        "body": message.body,
        "rewards": reward_views(db, message.rewards or []),
        "audience": message.audience,
        "targets": message.targets or [],
        "status": message.status,
        "phase": phase,
        "read_count": int(stats[0]),
        "claim_count": int(stats[1]),
        "created_by": message.created_by,
        "created_at": aware(message.created_at).isoformat(),
        "expires_at": aware(message.expires_at).isoformat(),
    }


@router.get("/admin/v1/mail")
def admin_list(_: Reader, db: Db, q: str = Query(default="", max_length=80)):
    query = select(MailMessage).order_by(MailMessage.created_at.desc()).limit(200)
    if q.strip():
        query = query.where(MailMessage.title.ilike(f"%{q.strip()}%"))
    return {"messages": [admin_view(db, m) for m in db.scalars(query)]}


@router.post("/admin/v1/mail", status_code=201)
def send(body: NewMail, admin: Operator, db: Db):
    from app.admin_api import ItemCatalog

    targets = list(dict.fromkeys(t.strip() for t in body.targets if t.strip()))
    if body.audience == "players":
        if not targets:
            raise HTTPException(422, "Choose at least one player")
        found = set(db.scalars(select(Account.id).where(Account.id.in_(targets))))
        missing = [t for t in targets if t not in found]
        if missing:
            raise HTTPException(404, f"Unknown players: {', '.join(missing[:5])}")
    else:
        targets = []
    for reward in body.rewards:
        if reward.type == "item" and (
            not reward.item_id or db.get(ItemCatalog, reward.item_id) is None
        ):
            raise HTTPException(404, f"Unknown items: {reward.item_id}")
    message = MailMessage(
        id=str(uuid.uuid4()),
        category=body.category,
        sender=body.sender.strip(),
        title=body.title.strip(),
        body=body.body.strip(),
        rewards=[r.model_dump(exclude_none=True) for r in body.rewards],
        audience=body.audience,
        targets=targets,
        status="active",
        created_by=admin.username,
        created_at=now(),
        expires_at=now() + timedelta(days=body.expires_days),
    )
    db.add(message)
    audit(
        db,
        admin,
        "mail.send",
        "mail",
        message.id,
        title=message.title,
        audience=message.audience,
        targets=len(targets),
        rewards=message.rewards,
    )
    db.commit()
    return admin_view(db, message)


@router.post("/admin/v1/mail/{message_id}/recall")
def recall(message_id: str, body: Reason, admin: Operator, db: Db):
    message = db.get(MailMessage, message_id)
    if message is None:
        raise HTTPException(404, "Message not found")
    if message.status == "recalled":
        raise HTTPException(409, "Already recalled")
    message.status = "recalled"
    audit(db, admin, "mail.recall", "mail", message.id, body.reason)
    db.commit()
    return admin_view(db, message)


@router.get("/admin/v1/mail/players")
def find_players(_: Reader, db: Db, q: str = Query(min_length=2, max_length=36)):
    """Search players to address (name, login or exact id)."""
    needle = q.strip()
    rows = db.scalars(
        select(Account)
        .where(
            or_(
                Account.id == needle,
                Account.display_name.ilike(f"%{needle}%"),
                Account.username.ilike(f"%{needle}%"),
            )
        )
        .limit(20)
    )
    return {"players": [{"id": a.id, "name": a.display_name, "username": a.username} for a in rows]}
