"""Admin portal modules: players, items, events, giftcodes, shop offers, live rooms,
economy view, reports and server health. Every write goes through the audit log.

Only data the stack really has is reported: there is no wallet, payment or match
history yet, and the UI says so instead of inventing numbers.
"""

import json
import os
import secrets
import string
import time
import urllib.request
import uuid
from collections import Counter
from datetime import UTC, date, datetime, timedelta
from typing import Annotated, Literal

import jwt
from fastapi import APIRouter, HTTPException, Query, Request
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import (
    JSON,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
    or_,
    select,
    text,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import AdminUser, AuditLog, Moderator, Operator, Reader, audit
from app.economy import (
    MAX_ICON_BYTES,
    PACKS,
    LedgerEntry,
    Stock,
    Wallet,
    entry_view,
    locked_wallet,
    post_ledger,
    store_asset,
)
from app.main import (
    JWT_SECRET,
    ONLINE_WINDOW,
    Account,
    AccountSanction,
    Base,
    Db,
    Identity,
    InventoryItem,
    active_ban,
    limiter,
)
from app.social import ChatMessage, FriendRequest, Guild, GuildMember, guild_of

router = APIRouter(prefix="/admin/v1")
player_router = APIRouter(prefix="/v1")
STARTED = time.time()
Category = Literal[
    "consumable", "outfit", "hat", "wings", "bomb_skin", "effect", "pet", "accessory"
]
Rarity = Literal["common", "rare", "epic", "legendary"]
Currency = Literal["gold", "gem"]


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime | None) -> datetime | None:
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


class Reason(BaseModel):
    reason: str = Field(min_length=5, max_length=500)


# ---------------------------------------------------------------- Players


def mask(email: str | None) -> str | None:
    if not email:
        return None
    name, _, domain = email.partition("@")
    return f"{name[:1]}***@{domain}"


def account_status(db: Session, account: Account) -> str:
    """locked: active ban; unlocked: was banned, ban lifted or expired; active: never banned."""
    if active_ban(db, account.id):
        return "locked"
    ever = db.scalar(
        select(func.count())
        .select_from(AccountSanction)
        .where(AccountSanction.account_id == account.id)
    )
    return "unlocked" if ever else "active"


def is_online(account: Account) -> bool:
    seen = aware(account.last_seen_at)
    return bool(seen and seen > now() - ONLINE_WINDOW)


def account_row(db: Session, account: Account, admin: AdminUser) -> dict:
    vip = aware(account.vip_until)
    wallet = db.get(Wallet, account.id)
    items = db.scalar(
        select(func.count())
        .select_from(InventoryItem)
        .where(InventoryItem.account_id == account.id)
    )
    return {
        "id": account.id,
        "username": account.username,
        "name": account.display_name,
        "guest": account.username is None,
        # Viewers see a masked address; operators need it to help with recovery.
        "email": account.email if admin.role != "viewer" else mask(account.email),
        "created_at": account.created_at,
        "last_login_at": account.last_login_at,
        "vip": bool(vip and vip > now()),
        "banned": active_ban(db, account.id) is not None,
        "status": account_status(db, account),
        "online": is_online(account),
        "last_seen_at": account.last_seen_at,
        "gold": wallet.gold if wallet else None,
        "gem": wallet.gem if wallet else None,
        "items": items,
    }


@router.get("/accounts")
def accounts(
    admin: Reader,
    db: Db,
    q: str = "",
    status: Literal["all", "registered", "guest", "banned", "unlocked", "online"] = "all",
    page: Annotated[int, Query(ge=1)] = 1,
    size: Annotated[int, Query(ge=1, le=100)] = 20,
):
    query = select(Account)
    term = q.strip().lower().replace("%", "")
    if term:
        query = query.where(
            or_(
                Account.username.like(f"%{term}%"),
                Account.display_name.like(f"%{term}%"),
                Account.email.like(f"%{term}%"),
                Account.id == term,
            )
        )
    if status == "registered":
        query = query.where(Account.username.is_not(None))
    elif status == "guest":
        query = query.where(Account.username.is_(None))
    elif status == "banned":
        banned = select(AccountSanction.account_id).where(AccountSanction.revoked_at.is_(None))
        query = query.where(Account.id.in_(banned))
    elif status == "unlocked":
        lifted = select(AccountSanction.account_id).where(AccountSanction.revoked_at.is_not(None))
        current = select(AccountSanction.account_id).where(AccountSanction.revoked_at.is_(None))
        query = query.where(Account.id.in_(lifted), Account.id.not_in(current))
    elif status == "online":
        query = query.where(Account.last_seen_at >= now() - ONLINE_WINDOW)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    rows = db.scalars(
        query.order_by(Account.created_at.desc().nulls_last(), Account.display_name)
        .offset((page - 1) * size)
        .limit(size)
    )
    return {
        "items": [account_row(db, a, admin) for a in rows],
        "total": total,
        "page": page,
        "size": size,
    }


def sanction_view(row: AccountSanction) -> dict:
    expires = aware(row.expires_at)
    active = row.revoked_at is None and (expires is None or expires > now())
    return {
        "id": row.id,
        "kind": row.kind,
        "reason": row.reason,
        "created_by": row.created_by,
        "created_at": row.created_at,
        "expires_at": row.expires_at,
        "revoked_at": row.revoked_at,
        "active": active,
    }


def get_account(db: Session, account_id: str) -> Account:
    account = db.get(Account, account_id)
    if account is None:
        raise HTTPException(404, "Account not found")
    return account


@router.get("/accounts/{account_id}")
def account_detail(account_id: str, admin: Reader, db: Db):
    account = get_account(db, account_id)
    items = list(
        db.scalars(select(InventoryItem.item_id).where(InventoryItem.account_id == account.id))
    )
    catalog = {i.id: i for i in db.scalars(select(ItemCatalog).where(ItemCatalog.id.in_(items)))}
    friends = db.scalar(
        select(func.count())
        .select_from(FriendRequest)
        .where(
            FriendRequest.status == "accepted",
            or_(FriendRequest.sender_id == account.id, FriendRequest.receiver_id == account.id),
        )
    )
    guild = guild_of(db, account.id)
    messages = db.scalars(
        select(ChatMessage)
        .where(ChatMessage.sender_id == account.id)
        .order_by(ChatMessage.id.desc())
        .limit(20)
    )
    sanctions = db.scalars(
        select(AccountSanction)
        .where(AccountSanction.account_id == account.id)
        .order_by(AccountSanction.created_at.desc())
    )
    redemptions = db.scalars(
        select(GiftcodeRedemption)
        .where(GiftcodeRedemption.account_id == account.id)
        .order_by(GiftcodeRedemption.created_at.desc())
    )
    from app.matches import player_stats

    stock = db.scalars(select(Stock).where(Stock.account_id == account.id, Stock.quantity > 0))
    ledger = db.scalars(
        select(LedgerEntry)
        .where(LedgerEntry.account_id == account.id)
        .order_by(LedgerEntry.id.desc())
        .limit(50)
    )
    return {
        **account_row(db, account, admin),
        "vip_until": account.vip_until,
        "stock": [{"item_id": s.item_id, "quantity": s.quantity} for s in stock],
        "ledger": [entry_view(e) for e in ledger],
        "stats": player_stats(db, account.id),
        "inventory": [
            {
                "item_id": item,
                "name": catalog[item].name if item in catalog else item,
                "category": catalog[item].category if item in catalog else None,
                "rarity": catalog[item].rarity if item in catalog else None,
                "icon": catalog[item].icon if item in catalog else None,
            }
            for item in items
        ],
        "friends": friends,
        "guild": guild.name if guild else None,
        "sanctions": [sanction_view(s) for s in sanctions],
        "messages": [
            {"id": m.id, "channel": m.channel, "body": m.body, "created_at": m.created_at}
            for m in messages
        ],
        "giftcodes": [
            {"code": db.get(Giftcode, r.giftcode_id).code, "created_at": r.created_at}
            for r in redemptions
        ],
    }


class AccountPatch(Reason):
    display_name: str | None = Field(default=None, min_length=2, max_length=24)
    email: str | None = Field(default=None, max_length=254)
    vip_until: datetime | None = None
    clear_vip: bool = False


@router.patch("/accounts/{account_id}")
def edit_account(account_id: str, body: AccountPatch, admin: Moderator, db: Db):
    account = get_account(db, account_id)
    before = account_row(db, account, admin)
    if body.display_name is not None:
        account.display_name = body.display_name.strip()
    if body.email is not None:
        email = body.email.strip().lower() or None
        if email and ("@" not in email or "." not in email.split("@")[-1]):
            raise HTTPException(422, "Invalid email")
        account.email = email
    if body.clear_vip:
        account.vip_until = None
    elif body.vip_until is not None:
        account.vip_until = aware(body.vip_until)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Email already used by another account") from exc
    audit(
        db,
        admin,
        "account.edit",
        "account",
        account.id,
        body.reason,
        before={k: before[k] for k in ("name", "email", "vip")},
        after={"name": account.display_name, "email": account.email},
    )
    db.commit()
    return account_row(db, account, admin)


class WalletAdjust(Reason):
    currency: Literal["gold", "gem"]
    delta: int = Field(ge=-10_000_000, le=10_000_000)


@router.post("/accounts/{account_id}/wallet")
def adjust_wallet(account_id: str, body: WalletAdjust, admin: Operator, db: Db):
    if body.delta == 0:
        raise HTTPException(422, "delta must not be 0")
    account = get_account(db, account_id)
    wallet = locked_wallet(db, account)
    post_ledger(
        db,
        wallet,
        body.currency,
        body.delta,
        "admin_adjust",
        f"admin:{admin.id}:{uuid.uuid4().hex}",
        note=body.reason,
        actor=admin.username,
    )
    audit(
        db,
        admin,
        "wallet.adjust",
        "account",
        account.id,
        body.reason,
        currency=body.currency,
        delta=body.delta,
    )
    db.commit()
    return {"gold": wallet.gold, "gem": wallet.gem}


@router.get("/transactions")
def transactions(
    _: Reader,
    db: Db,
    account_id: str = "",
    kind: str = "",
    currency: str = "",
    page: Annotated[int, Query(ge=1)] = 1,
    size: Annotated[int, Query(ge=1, le=100)] = 30,
):
    query = select(LedgerEntry.id)
    if account_id:
        query = query.where(LedgerEntry.account_id == account_id)
    if kind:
        query = query.where(LedgerEntry.kind == kind)
    if currency:
        query = query.where(LedgerEntry.currency == currency)
    total = db.scalar(select(func.count()).select_from(query.subquery()))
    rows = db.execute(
        select(LedgerEntry, Account.display_name)
        .join(Account, Account.id == LedgerEntry.account_id)
        .where(LedgerEntry.id.in_(query))
        .order_by(LedgerEntry.id.desc())
        .offset((page - 1) * size)
        .limit(size)
    ).all()
    topups = list(db.scalars(select(LedgerEntry).where(LedgerEntry.kind == "topup")))
    total_of = lambda column: db.scalar(select(func.coalesce(func.sum(column), 0)))  # noqa: E731
    return {
        "items": [
            {**entry_view(e), "account_id": e.account_id, "account_name": name} for e, name in rows
        ],
        "total": total,
        "page": page,
        "size": size,
        "summary": {
            "topups": len(topups),
            "gem_topped_up": sum(e.delta for e in topups if e.currency == "gem"),
            "sandbox_vnd": sum(e.amount_vnd or 0 for e in topups),
            "gold_exchanged": db.scalar(
                select(func.coalesce(func.sum(LedgerEntry.delta), 0)).where(
                    LedgerEntry.kind == "exchange", LedgerEntry.currency == "gold"
                )
            ),
            "purchases": db.scalar(
                select(func.count()).select_from(LedgerEntry).where(LedgerEntry.kind == "purchase")
            ),
            "wallets": db.scalar(select(func.count()).select_from(Wallet)),
            "gold_total": total_of(Wallet.gold),
            "gem_total": total_of(Wallet.gem),
        },
        "packs": PACKS,
    }


class SanctionBody(Reason):
    hours: int | None = Field(default=None, ge=1, le=24 * 365)


@router.post("/accounts/{account_id}/sanctions", status_code=201)
def ban(account_id: str, body: SanctionBody, admin: Moderator, db: Db):
    account = get_account(db, account_id)
    if active_ban(db, account.id):
        raise HTTPException(409, "Account already suspended")
    row = AccountSanction(
        id=str(uuid.uuid4()),
        account_id=account.id,
        kind="ban",
        reason=body.reason,
        created_by=admin.username,
        created_at=now(),
        expires_at=now() + timedelta(hours=body.hours) if body.hours else None,
    )
    db.add(row)
    audit(db, admin, "account.ban", "account", account.id, body.reason, hours=body.hours)
    db.commit()
    return sanction_view(row)


@router.post("/accounts/{account_id}/sanctions/{sanction_id}/revoke")
def unban(account_id: str, sanction_id: str, body: Reason, admin: Moderator, db: Db):
    row = db.get(AccountSanction, sanction_id)
    if row is None or row.account_id != account_id or row.revoked_at is not None:
        raise HTTPException(404, "Active sanction not found")
    row.revoked_at = now()
    audit(db, admin, "account.unban", "account", account_id, body.reason, sanction=sanction_id)
    db.commit()
    return sanction_view(row)


class GrantBody(Reason):
    item_id: str = Field(min_length=1, max_length=64)


@router.post("/accounts/{account_id}/inventory", status_code=201)
def grant_item(account_id: str, body: GrantBody, admin: Operator, db: Db):
    account = get_account(db, account_id)
    if db.get(ItemCatalog, body.item_id) is None:
        raise HTTPException(404, "Item not in catalog")
    if db.get(InventoryItem, (account.id, body.item_id)):
        raise HTTPException(409, "Player already owns this item")
    db.add(InventoryItem(account_id=account.id, item_id=body.item_id))
    audit(db, admin, "inventory.grant", "account", account.id, body.reason, item=body.item_id)
    db.commit()
    return {"item_id": body.item_id}


@router.post("/accounts/{account_id}/inventory/{item_id}/revoke")
def revoke_item(account_id: str, item_id: str, body: Reason, admin: Operator, db: Db):
    row = db.get(InventoryItem, (account_id, item_id))
    if row is None:
        raise HTTPException(404, "Player does not own this item")
    db.delete(row)
    audit(db, admin, "inventory.revoke", "account", account_id, body.reason, item=item_id)
    db.commit()
    return {"item_id": item_id}


@router.post("/chat/{message_id}/delete")
def delete_message(message_id: int, body: Reason, admin: Moderator, db: Db):
    message = db.get(ChatMessage, message_id)
    if message is None:
        raise HTTPException(404, "Message not found")
    audit(
        db,
        admin,
        "chat.delete",
        "account",
        message.sender_id,
        body.reason,
        message=message_id,
        body=message.body,
    )
    db.delete(message)
    db.commit()
    return {"deleted": message_id}


# ---------------------------------------------------------------- Items


class ItemCatalog(Base):
    __tablename__ = "item_catalog"
    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    category: Mapped[str] = mapped_column(String(16))
    rarity: Mapped[str] = mapped_column(String(16))
    description: Mapped[str] = mapped_column(String(200), default="")
    price: Mapped[int] = mapped_column(Integer, default=0)
    currency: Mapped[str] = mapped_column(String(8), default="gold")
    duration_days: Mapped[int | None] = mapped_column(Integer)
    # Consumables: uses added to the stock per purchase ("×5" packs give 5).
    quantity: Mapped[int] = mapped_column(Integer, default=1)
    icon: Mapped[str | None] = mapped_column(String(120))
    # Server copy of the art clients download (content-addressed, see economy.ItemAsset).
    icon_sha256: Mapped[str | None] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(12), default="draft")
    updated_by: Mapped[str] = mapped_column(String(32), default="system")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def item_view(item: ItemCatalog) -> dict:
    return {
        "id": item.id,
        "name": item.name,
        "category": item.category,
        "rarity": item.rarity,
        "description": item.description,
        "price": item.price,
        "currency": item.currency,
        "duration_days": item.duration_days,
        "quantity": item.quantity or 1,
        "icon": item.icon,
        "icon_sha256": item.icon_sha256,
        "status": item.status,
        "updated_by": item.updated_by,
        "updated_at": item.updated_at,
    }


class ItemFields(BaseModel):
    name: str = Field(min_length=2, max_length=80)
    category: Category
    rarity: Rarity
    description: str = Field(default="", max_length=200)
    price: int = Field(ge=0, le=10_000_000)
    currency: Currency = "gold"
    duration_days: int | None = Field(default=None, ge=1, le=3650)
    quantity: int = Field(default=1, ge=1, le=99)
    icon: str | None = Field(default=None, max_length=120, pattern=r"^[a-z0-9_/.-]+\.png$")


class NewItem(ItemFields):
    id: str = Field(min_length=3, max_length=64, pattern=r"^[a-z0-9_]+$")


class ItemPatch(BaseModel):
    name: str | None = Field(default=None, min_length=2, max_length=80)
    category: Category | None = None
    rarity: Rarity | None = None
    description: str | None = Field(default=None, max_length=200)
    price: int | None = Field(default=None, ge=0, le=10_000_000)
    currency: Currency | None = None
    duration_days: int | None = Field(default=None, ge=1, le=3650)
    quantity: int | None = Field(default=None, ge=1, le=99)
    icon: str | None = Field(default=None, max_length=120, pattern=r"^[a-z0-9_/.-]+\.png$")


@router.get("/items")
def items(
    _: Reader,
    db: Db,
    q: str = "",
    category: str = "",
    status: str = "",
):
    query = select(ItemCatalog).order_by(ItemCatalog.category, ItemCatalog.name)
    if q.strip():
        term = f"%{q.strip().lower().replace('%', '')}%"
        query = query.where(or_(func.lower(ItemCatalog.name).like(term), ItemCatalog.id.like(term)))
    if category:
        query = query.where(ItemCatalog.category == category)
    if status:
        query = query.where(ItemCatalog.status == status)
    owners = dict(
        db.execute(
            select(InventoryItem.item_id, func.count()).group_by(InventoryItem.item_id)
        ).all()
    )
    return {"items": [{**item_view(i), "owners": owners.get(i.id, 0)} for i in db.scalars(query)]}


@router.post("/items", status_code=201)
def create_item(body: NewItem, admin: Operator, db: Db):
    if db.get(ItemCatalog, body.id):
        raise HTTPException(409, "Item id already exists")
    item = ItemCatalog(
        **body.model_dump(), status="draft", updated_by=admin.username, updated_at=now()
    )
    db.add(item)
    audit(db, admin, "item.create", "item", item.id, after=item_view(item))
    db.commit()
    return item_view(item)


def get_item(db: Session, item_id: str) -> ItemCatalog:
    item = db.get(ItemCatalog, item_id)
    if item is None:
        raise HTTPException(404, "Item not found")
    return item


@router.patch("/items/{item_id}")
def update_item(item_id: str, body: ItemPatch, admin: Operator, db: Db):
    item = get_item(db, item_id)
    before = item_view(item)
    for key, value in body.model_dump(exclude_unset=True).items():
        setattr(item, key, value)
    item.updated_by = admin.username
    item.updated_at = now()
    audit(db, admin, "item.update", "item", item.id, before=before, after=item_view(item))
    db.commit()
    return item_view(item)


@router.post("/items/{item_id}/icon")
async def upload_icon(item_id: str, request: Request, admin: Operator, db: Db):
    """Raw PNG body (<= 10 MB). Clients pick it up through the catalog hash."""
    length = request.headers.get("content-length")
    if length and int(length) > MAX_ICON_BYTES:
        raise HTTPException(413, "Icon larger than 10 MB")
    content = await request.body()
    item = get_item(db, item_id)
    asset = store_asset(db, content)
    before = item.icon_sha256
    item.icon_sha256 = asset.sha256
    item.updated_by = admin.username
    item.updated_at = now()
    audit(db, admin, "item.icon", "item", item.id, before=before, after=asset.sha256)
    db.commit()
    return item_view(item)


@router.post("/items/{item_id}/{action}")
def item_status(item_id: str, action: Literal["publish", "hide"], admin: Operator, db: Db):
    item = get_item(db, item_id)
    item.status = "published" if action == "publish" else "hidden"
    item.updated_by = admin.username
    item.updated_at = now()
    audit(db, admin, f"item.{action}", "item", item.id)
    db.commit()
    return item_view(item)


# ---------------------------------------------------------------- Events


class GameEvent(Base):
    __tablename__ = "events"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(80))
    kind: Mapped[str] = mapped_column(String(16))
    description: Mapped[str] = mapped_column(String(500), default="")
    status: Mapped[str] = mapped_column(String(12), default="draft")
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    end_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    reward_items: Mapped[str] = mapped_column(Text, default="[]")
    created_by: Mapped[str] = mapped_column(String(32))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    # LiveOps (app/liveops.py): claim window, chapters/quests/shop JSON, publish version.
    claim_end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    config: Mapped[dict | None] = mapped_column(JSON)
    version: Mapped[int] = mapped_column(Integer, default=0)


EventKind = Literal[
    "login", "match", "rank", "collect", "shop", "custom", "story", "challenge", "boss"
]


def event_phase(event: GameEvent) -> str:
    """Stored status is draft/published/paused; the schedule decides the rest."""
    if event.status != "published":
        return event.status
    current = now()
    if current < aware(event.start_at):
        return "scheduled"
    if current > aware(event.end_at):
        return "ended"
    return "running"


def event_view(event: GameEvent) -> dict:
    return {
        "id": event.id,
        "name": event.name,
        "kind": event.kind,
        "description": event.description,
        "status": event.status,
        "phase": event_phase(event),
        "start_at": event.start_at,
        "end_at": event.end_at,
        "reward_items": json.loads(event.reward_items or "[]"),
        "claim_end_at": event.claim_end_at,
        "config": event.config or {},
        "version": event.version or 0,
        "created_by": event.created_by,
        "updated_at": event.updated_at,
    }


class EventFields(BaseModel):
    name: str = Field(min_length=3, max_length=80)
    kind: EventKind
    description: str = Field(default="", max_length=500)
    start_at: datetime
    end_at: datetime
    reward_items: list[str] = Field(default_factory=list, max_length=10)
    claim_end_at: datetime | None = None
    config: dict | None = None

    @field_validator("end_at")
    @classmethod
    def after_start(cls, value: datetime, info) -> datetime:
        start = info.data.get("start_at")
        if start and aware(value) <= aware(start):
            raise ValueError("end_at must be after start_at")
        return value


def check_rewards(db: Session, ids: list[str]) -> None:
    missing = [i for i in ids if db.get(ItemCatalog, i) is None]
    if missing:
        raise HTTPException(422, f"Unknown items: {', '.join(missing)}")


def checked_config(db: Session, body: "EventFields") -> dict:
    """Validates chapters/quests/shop (app.liveops); errors block the save."""
    from app.liveops import EventConfig, validate_event

    try:
        config = EventConfig(**(body.config or {}))
    except ValueError as exc:
        raise HTTPException(422, {"errors": [str(exc)[:500]], "warnings": []}) from exc
    result = validate_event(db, config, body.start_at, body.end_at, body.claim_end_at)
    if not result["ok"]:
        raise HTTPException(422, {"errors": result["errors"], "warnings": result["warnings"]})
    return config.model_dump()


@router.get("/events")
def events(_: Reader, db: Db):
    rows = db.scalars(select(GameEvent).order_by(GameEvent.start_at.desc()))
    return {"events": [event_view(e) for e in rows]}


@router.post("/events", status_code=201)
def create_event(body: EventFields, admin: Operator, db: Db):
    check_rewards(db, body.reward_items)
    config = checked_config(db, body)
    event = GameEvent(
        id=str(uuid.uuid4()),
        name=body.name,
        kind=body.kind,
        description=body.description,
        status="draft",
        start_at=aware(body.start_at),
        end_at=aware(body.end_at),
        reward_items=json.dumps(body.reward_items),
        claim_end_at=aware(body.claim_end_at) if body.claim_end_at else None,
        config=config,
        version=0,
        created_by=admin.username,
        updated_at=now(),
    )
    db.add(event)
    audit(db, admin, "event.create", "event", event.id, name=body.name)
    db.commit()
    return event_view(event)


def get_event(db: Session, event_id: str) -> GameEvent:
    event = db.get(GameEvent, event_id)
    if event is None:
        raise HTTPException(404, "Event not found")
    return event


@router.put("/events/{event_id}")
def update_event(event_id: str, body: EventFields, admin: Operator, db: Db):
    event = get_event(db, event_id)
    if event_phase(event) == "running":
        raise HTTPException(409, "Pause the event before editing it")
    check_rewards(db, body.reward_items)
    config = checked_config(db, body)
    before = event_view(event)
    event.name = body.name
    event.kind = body.kind
    event.description = body.description
    event.start_at = aware(body.start_at)
    event.end_at = aware(body.end_at)
    event.reward_items = json.dumps(body.reward_items)
    event.claim_end_at = aware(body.claim_end_at) if body.claim_end_at else None
    event.config = config
    event.updated_at = now()
    audit(db, admin, "event.update", "event", event.id, before=before, after=event_view(event))
    db.commit()
    return event_view(event)


@router.post("/events/{event_id}/{action}")
def event_action(
    event_id: str, action: Literal["publish", "pause", "resume"], admin: Operator, db: Db
):
    event = get_event(db, event_id)
    allowed = {"publish": ("draft",), "pause": ("published",), "resume": ("paused",)}
    if event.status not in allowed[action]:
        raise HTTPException(409, f"Cannot {action} an event that is {event.status}")
    event.status = "paused" if action == "pause" else "published"
    event.updated_at = now()
    if action != "pause":
        from app.liveops import snapshot

        snapshot(db, event, admin.username)
    audit(db, admin, f"event.{action}", "event", event.id)
    db.commit()
    return event_view(event)


# ---------------------------------------------------------------- Giftcodes


class Giftcode(Base):
    __tablename__ = "giftcodes"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    code: Mapped[str] = mapped_column(String(32), unique=True)
    name: Mapped[str] = mapped_column(String(80))
    reward_items: Mapped[str] = mapped_column(Text, default="[]")
    max_redemptions: Mapped[int] = mapped_column(Integer)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    status: Mapped[str] = mapped_column(String(12), default="active")
    created_by: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class GiftcodeRedemption(Base):
    __tablename__ = "giftcode_redemptions"
    __table_args__ = (UniqueConstraint("giftcode_id", "account_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    giftcode_id: Mapped[str] = mapped_column(ForeignKey("giftcodes.id", ondelete="CASCADE"))
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def used(db: Session, code: Giftcode) -> int:
    return db.scalar(
        select(func.count())
        .select_from(GiftcodeRedemption)
        .where(GiftcodeRedemption.giftcode_id == code.id)
    )


def code_phase(code: Giftcode, count: int) -> str:
    if code.status != "active":
        return code.status
    current = now()
    if current < aware(code.starts_at):
        return "scheduled"
    if current > aware(code.expires_at):
        return "expired"
    if count >= code.max_redemptions:
        return "exhausted"
    return "active"


def code_view(db: Session, code: Giftcode) -> dict:
    count = used(db, code)
    return {
        "id": code.id,
        "code": code.code,
        "name": code.name,
        "reward_items": json.loads(code.reward_items or "[]"),
        "max_redemptions": code.max_redemptions,
        "used": count,
        "starts_at": code.starts_at,
        "expires_at": code.expires_at,
        "status": code.status,
        "phase": code_phase(code, count),
        "created_by": code.created_by,
        "created_at": code.created_at,
    }


class NewGiftcode(BaseModel):
    code: str | None = Field(default=None, min_length=4, max_length=32, pattern=r"^[A-Za-z0-9-]+$")
    name: str = Field(min_length=3, max_length=80)
    reward_items: list[str] = Field(min_length=1, max_length=10)
    max_redemptions: int = Field(ge=1, le=1_000_000)
    starts_at: datetime | None = None
    expires_at: datetime


def random_code() -> str:
    alphabet = string.ascii_uppercase + string.digits
    alphabet = alphabet.translate(str.maketrans("", "", "0O1I"))
    return "BUP-" + "".join(secrets.choice(alphabet) for _ in range(8))


@router.get("/giftcodes")
def giftcodes(_: Reader, db: Db, q: str = ""):
    query = select(Giftcode).order_by(Giftcode.created_at.desc())
    if q.strip():
        term = f"%{q.strip().upper().replace('%', '')}%"
        query = query.where(or_(Giftcode.code.like(term), func.upper(Giftcode.name).like(term)))
    return {"giftcodes": [code_view(db, c) for c in db.scalars(query)]}


@router.post("/giftcodes", status_code=201)
def create_giftcode(body: NewGiftcode, admin: Operator, db: Db):
    check_rewards(db, body.reward_items)
    starts = aware(body.starts_at) or now()
    if aware(body.expires_at) <= starts:
        raise HTTPException(422, "expires_at must be after starts_at")
    code = Giftcode(
        id=str(uuid.uuid4()),
        code=(body.code or random_code()).upper(),
        name=body.name,
        reward_items=json.dumps(body.reward_items),
        max_redemptions=body.max_redemptions,
        starts_at=starts,
        expires_at=aware(body.expires_at),
        status="active",
        created_by=admin.username,
        created_at=now(),
    )
    db.add(code)
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Giftcode already exists") from exc
    audit(db, admin, "giftcode.create", "giftcode", code.id, code=code.code)
    db.commit()
    return code_view(db, code)


@router.post("/giftcodes/{code_id}/{action}")
def giftcode_status(code_id: str, action: Literal["disable", "enable"], admin: Operator, db: Db):
    code = db.get(Giftcode, code_id)
    if code is None:
        raise HTTPException(404, "Giftcode not found")
    code.status = "disabled" if action == "disable" else "active"
    audit(db, admin, f"giftcode.{action}", "giftcode", code.id, code=code.code)
    db.commit()
    return code_view(db, code)


@router.get("/giftcodes/{code_id}/redemptions")
def redemptions(code_id: str, _: Reader, db: Db):
    rows = db.execute(
        select(GiftcodeRedemption, Account)
        .join(Account, Account.id == GiftcodeRedemption.account_id)
        .where(GiftcodeRedemption.giftcode_id == code_id)
        .order_by(GiftcodeRedemption.created_at.desc())
        .limit(500)
    ).all()
    return {
        "redemptions": [
            {"account_id": a.id, "name": a.display_name, "created_at": r.created_at}
            for r, a in rows
        ]
    }


class RedeemBody(BaseModel):
    code: str = Field(min_length=4, max_length=32)


@player_router.post("/giftcodes/redeem")
def redeem(body: RedeemBody, account: Identity, db: Db):
    """Player side: one redemption per account, quota checked under a row lock."""
    query = select(Giftcode).where(Giftcode.code == body.code.strip().upper())
    if db.bind.dialect.name == "postgresql":
        query = query.with_for_update()
    code = db.scalar(query)
    if code is None:
        raise HTTPException(404, "Giftcode not found")
    phase = code_phase(code, used(db, code))
    if phase != "active":
        raise HTTPException(409, f"Giftcode {phase}")
    db.add(
        GiftcodeRedemption(
            id=str(uuid.uuid4()), giftcode_id=code.id, account_id=account.id, created_at=now()
        )
    )
    try:
        db.flush()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Giftcode already redeemed") from exc
    granted = []
    for item_id in json.loads(code.reward_items or "[]"):
        if db.get(InventoryItem, (account.id, item_id)) is None:
            db.add(InventoryItem(account_id=account.id, item_id=item_id))
            granted.append(item_id)
    db.commit()
    return {"code": code.code, "granted": granted}


# ---------------------------------------------------------------- Shop


class ShopOffer(Base):
    __tablename__ = "shop_offers"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    item_id: Mapped[str] = mapped_column(ForeignKey("item_catalog.id"))
    price: Mapped[int] = mapped_column(Integer)
    currency: Mapped[str] = mapped_column(String(8))
    discount_percent: Mapped[int] = mapped_column(Integer, default=0)
    status: Mapped[str] = mapped_column(String(12), default="draft")
    start_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    end_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_by: Mapped[str] = mapped_column(String(32))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def offer_view(db: Session, offer: ShopOffer) -> dict:
    item = db.get(ItemCatalog, offer.item_id)
    phase = offer.status
    if offer.status == "published":
        current = now()
        if current < aware(offer.start_at):
            phase = "scheduled"
        elif offer.end_at and current > aware(offer.end_at):
            phase = "ended"
        else:
            phase = "on_sale"
    return {
        "id": offer.id,
        "item_id": offer.item_id,
        "item_name": item.name if item else offer.item_id,
        "icon": item.icon if item else None,
        "price": offer.price,
        "final_price": offer.price * (100 - offer.discount_percent) // 100,
        "currency": offer.currency,
        "discount_percent": offer.discount_percent,
        "status": offer.status,
        "phase": phase,
        "start_at": offer.start_at,
        "end_at": offer.end_at,
        "updated_by": offer.updated_by,
        "updated_at": offer.updated_at,
    }


class OfferFields(BaseModel):
    item_id: str = Field(min_length=1, max_length=64)
    price: int = Field(ge=0, le=10_000_000)
    currency: Currency
    discount_percent: int = Field(default=0, ge=0, le=90)
    start_at: datetime | None = None
    end_at: datetime | None = None


@router.get("/shop/offers")
def offers(_: Reader, db: Db):
    rows = db.scalars(select(ShopOffer).order_by(ShopOffer.updated_at.desc()))
    return {"offers": [offer_view(db, o) for o in rows]}


@router.post("/shop/offers", status_code=201)
def create_offer(body: OfferFields, admin: Operator, db: Db):
    item = db.get(ItemCatalog, body.item_id)
    if item is None:
        raise HTTPException(404, "Item not in catalog")
    start = aware(body.start_at) or now()
    if body.end_at and aware(body.end_at) <= start:
        raise HTTPException(422, "end_at must be after start_at")
    offer = ShopOffer(
        id=str(uuid.uuid4()),
        item_id=item.id,
        price=body.price,
        currency=body.currency,
        discount_percent=body.discount_percent,
        status="draft",
        start_at=start,
        end_at=aware(body.end_at),
        updated_by=admin.username,
        updated_at=now(),
    )
    db.add(offer)
    audit(db, admin, "offer.create", "offer", offer.id, item=item.id, price=body.price)
    db.commit()
    return offer_view(db, offer)


@router.post("/shop/offers/{offer_id}/{action}")
def offer_status(offer_id: str, action: Literal["publish", "pause"], admin: Operator, db: Db):
    offer = db.get(ShopOffer, offer_id)
    if offer is None:
        raise HTTPException(404, "Offer not found")
    if action == "publish":
        item = db.get(ItemCatalog, offer.item_id)
        if item is None or item.status != "published":
            raise HTTPException(409, "Publish the item before selling it")
    offer.status = "published" if action == "publish" else "paused"
    offer.updated_by = admin.username
    offer.updated_at = now()
    audit(db, admin, f"offer.{action}", "offer", offer.id)
    db.commit()
    return offer_view(db, offer)


@player_router.get("/shop/offers")
def public_offers(db: Db):
    rows = db.scalars(select(ShopOffer).where(ShopOffer.status == "published"))
    return {"offers": [o for o in (offer_view(db, r) for r in rows) if o["phase"] == "on_sale"]}


# ---------------------------------------------------------------- Live rooms, economy


def arena_url() -> str:
    return os.environ.get("ARENA_URL", "http://arena:2567").rstrip("/")


def arena_get(path: str, token: str | None = None) -> tuple[int, dict | None, float]:
    request = urllib.request.Request(arena_url() + path)
    if token:
        request.add_header("Authorization", "Bearer " + token)
    started = time.perf_counter()
    try:
        with urllib.request.urlopen(request, timeout=3) as response:
            body = response.read(65536)
            elapsed = (time.perf_counter() - started) * 1000
            try:
                return response.status, json.loads(body or b"{}"), elapsed
            except ValueError:
                return response.status, None, elapsed
    except (OSError, ValueError):
        return 0, None, (time.perf_counter() - started) * 1000


def live_rooms() -> dict:
    # Short-lived service identity; arena only lists waiting rooms with players.
    issued = now()
    token = jwt.encode(
        {
            "sub": "admin-portal",
            "name": "admin-portal",
            "iss": "suni-api",
            "aud": "suni-arena",
            "iat": issued,
            "exp": issued + timedelta(minutes=1),
        },
        JWT_SECRET,
        algorithm="HS256",
    )
    status, data, _ = arena_get("/rooms", token)
    if status != 200 or not isinstance(data, dict):
        return {"available": False, "rooms": [], "players": 0}
    rooms = data.get("rooms", [])
    return {
        "available": True,
        "rooms": rooms,
        "players": sum(int(r.get("players", 0)) for r in rooms),
    }


@router.get("/rooms/live")
def rooms_live(_: Reader):
    return live_rooms()


@router.get("/economy")
def economy(_: Reader, db: Db):
    ledger = db.scalars(
        select(AuditLog)
        .where(AuditLog.action.in_(["inventory.grant", "inventory.revoke"]))
        .order_by(AuditLog.id.desc())
        .limit(100)
    )
    redemptions = db.scalar(select(func.count()).select_from(GiftcodeRedemption))
    return {
        "wallets": False,
        "entries": [
            {
                "id": row.id,
                "action": row.action,
                "account_id": row.target_id,
                "item": json.loads(row.detail or "{}").get("item"),
                "reason": row.reason,
                "actor": row.actor_name,
                "created_at": row.created_at,
            }
            for row in ledger
        ],
        "giftcode_redemptions": redemptions,
    }


# ---------------------------------------------------------------- Reports and server


def daily(values: list[datetime | None], days: int) -> list[dict]:
    start = date.today() - timedelta(days=days - 1)
    counts = Counter(aware(v).date() for v in values if v is not None)
    return [
        {
            "day": (start + timedelta(days=i)).isoformat(),
            "count": counts.get(start + timedelta(days=i), 0),
        }
        for i in range(days)
    ]


@router.get("/reports/overview")
def overview(_: Reader, db: Db, days: Annotated[int, Query(ge=7, le=90)] = 14):
    current = now()
    since = current - timedelta(days=days)
    count = lambda query: db.scalar(select(func.count()).select_from(query.subquery()))  # noqa: E731
    registered = count(select(Account.id).where(Account.username.is_not(None)))
    total = count(select(Account.id))
    created = list(db.scalars(select(Account.created_at).where(Account.created_at >= since)))
    logins = list(db.scalars(select(Account.last_login_at).where(Account.last_login_at >= since)))
    chats = list(db.scalars(select(ChatMessage.created_at).where(ChatMessage.created_at >= since)))
    redeemed = list(
        db.scalars(
            select(GiftcodeRedemption.created_at).where(GiftcodeRedemption.created_at >= since)
        )
    )
    events_all = list(db.scalars(select(GameEvent)))
    live = live_rooms()
    from app.matches import counts_by_status, recent_counts

    topups = list(
        db.scalars(
            select(LedgerEntry.created_at).where(
                LedgerEntry.kind == "topup", LedgerEntry.created_at >= since
            )
        )
    )
    return {
        "generated_at": current,
        "accounts": {
            "total": total,
            "registered": registered,
            "guests": total - registered,
            "new_24h": sum(1 for v in created if aware(v) >= current - timedelta(hours=24)),
            "active_24h": sum(1 for v in logins if aware(v) >= current - timedelta(hours=24)),
            "banned": count(
                select(AccountSanction.account_id).where(AccountSanction.revoked_at.is_(None))
            ),
        },
        "social": {
            "guilds": count(select(Guild.id)),
            "guild_members": count(select(GuildMember.account_id)),
            "friendships": count(
                select(FriendRequest.id).where(FriendRequest.status == "accepted")
            ),
            "chat_24h": sum(1 for v in chats if aware(v) >= current - timedelta(hours=24)),
        },
        "liveops": {
            "events_running": sum(1 for e in events_all if event_phase(e) == "running"),
            "events_total": len(events_all),
            "items_published": count(
                select(ItemCatalog.id).where(ItemCatalog.status == "published")
            ),
            "giftcode_redemptions": count(select(GiftcodeRedemption.id)),
            "offers_on_sale": sum(
                1
                for o in db.scalars(select(ShopOffer).where(ShopOffer.status == "published"))
                if offer_view(db, o)["phase"] == "on_sale"
            ),
        },
        "live": {
            "available": live["available"],
            "rooms": len(live["rooms"]),
            "players": live["players"],
        },
        "online_now": count(
            select(Account.id).where(Account.last_seen_at >= current - ONLINE_WINDOW)
        ),
        "rooms": counts_by_status(db),
        "recent": recent_counts(db, current - timedelta(hours=24)),
        "series": {
            "registrations": daily(created, days),
            "logins": daily(logins, days),
            "chat": daily(chats, days),
            "redemptions": daily(redeemed, days),
            "topups": daily(topups, days),
        },
        "revenue": None,
    }


@router.get("/server")
def server(_: Reader, db: Db):
    checks = []
    started = time.perf_counter()
    try:
        db.execute(text("SELECT 1"))
        checks.append(
            {"name": "PostgreSQL", "ok": True, "ms": (time.perf_counter() - started) * 1000}
        )
    except Exception:
        checks.append({"name": "PostgreSQL", "ok": False, "ms": None})
    started = time.perf_counter()
    try:
        limiter.ping()
        checks.append({"name": "Redis", "ok": True, "ms": (time.perf_counter() - started) * 1000})
    except Exception:
        checks.append({"name": "Redis", "ok": False, "ms": None})
    status, _, elapsed = arena_get("/health")
    checks.append(
        {"name": "Arena (Colyseus)", "ok": status == 200, "ms": elapsed if status else None}
    )
    checks.insert(0, {"name": "Account API", "ok": True, "ms": 0})
    return {
        "checks": checks,
        "uptime_seconds": int(time.time() - STARTED),
        "mail_mode": os.environ.get("MAIL_MODE", "disabled"),
        "time": now(),
    }
