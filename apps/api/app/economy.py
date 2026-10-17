"""Server wallet, append-only ledger, item art and the public catalog.

Balances only change through ``post_ledger`` inside one transaction, with a unique
reference per entry so client retries never apply twice. Top-up packs are a
sandbox: phase 1 has no payment provider, nothing is charged, and every entry
is marked as such for the admin.
"""

import hashlib
import json
import struct
from datetime import UTC, datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Header, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import BigInteger, DateTime, ForeignKey, Integer, LargeBinary, String, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.main import Account, Base, Db, Identity, InventoryItem

router = APIRouter(prefix="/v1")
Currency = Literal["gold", "gem"]
WELCOME = {"gold": 5000, "gem": 100}
# Cheap commons so a new account can equip something before buying.
STARTER_ITEMS = ("outfit_mimi", "outfit_bombo", "outfit_kai", "bomb_skin_classic")
# Sandbox packs. amount_vnd is the list price shown to players; nothing is charged.
PACKS = {
    "gem_60": {"name": "60 kim cương", "currency": "gem", "amount": 60, "vnd": 20_000},
    "gem_330": {"name": "330 kim cương", "currency": "gem", "amount": 330, "vnd": 99_000},
    "gem_1080": {"name": "1.080 kim cương", "currency": "gem", "amount": 1080, "vnd": 299_000},
    "gold_5000": {"name": "5.000 vàng", "currency": "gold", "amount": 5000, "gem_cost": 50},
    "gold_12000": {"name": "12.000 vàng", "currency": "gold", "amount": 12000, "gem_cost": 100},
}
# Icons live in the database and every client downloads them: a generous cap,
# not unlimited, so one bad upload cannot fill the DB or stall catalog sync.
MAX_ICON_BYTES = 10 * 1024 * 1024
MAX_ICON_SIDE = 2048


def now() -> datetime:
    return datetime.now(UTC)


class Wallet(Base):
    __tablename__ = "wallets"
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    gold: Mapped[int] = mapped_column(BigInteger, default=0)
    gem: Mapped[int] = mapped_column(BigInteger, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class LedgerEntry(Base):
    __tablename__ = "wallet_ledger"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    currency: Mapped[str] = mapped_column(String(8))
    delta: Mapped[int] = mapped_column(BigInteger)
    balance_after: Mapped[int] = mapped_column(BigInteger)
    # welcome, topup, exchange, purchase, admin_adjust
    kind: Mapped[str] = mapped_column(String(16))
    reference: Mapped[str] = mapped_column(String(120), unique=True)
    item_id: Mapped[str | None] = mapped_column(String(64))
    amount_vnd: Mapped[int | None] = mapped_column(Integer)
    note: Mapped[str] = mapped_column(String(300), default="")
    actor: Mapped[str] = mapped_column(String(32), default="player")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class Stock(Base):
    """Consumables are counted, not owned once like cosmetics."""

    __tablename__ = "inventory_stock"
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    quantity: Mapped[int] = mapped_column(Integer, default=0)


class ItemAsset(Base):
    __tablename__ = "item_assets"
    sha256: Mapped[str] = mapped_column(String(64), primary_key=True)
    content: Mapped[bytes] = mapped_column(LargeBinary)
    content_type: Mapped[str] = mapped_column(String(32))
    size: Mapped[int] = mapped_column(Integer)
    width: Mapped[int] = mapped_column(Integer)
    height: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def png_size(content: bytes) -> tuple[int, int]:
    if len(content) < 24 or content[:8] != b"\x89PNG\r\n\x1a\n" or content[12:16] != b"IHDR":
        raise HTTPException(422, "Icon must be a PNG image")
    return struct.unpack(">II", content[16:24])


def store_asset(db: Session, content: bytes) -> ItemAsset:
    if len(content) > MAX_ICON_BYTES:
        raise HTTPException(413, "Icon larger than 10 MB")
    width, height = png_size(content)
    if not (16 <= width <= MAX_ICON_SIDE and 16 <= height <= MAX_ICON_SIDE):
        raise HTTPException(422, f"Icon must be 16-{MAX_ICON_SIDE} px")
    digest = hashlib.sha256(content).hexdigest()
    asset = db.get(ItemAsset, digest)
    if asset is None:
        asset = ItemAsset(
            sha256=digest,
            content=content,
            content_type="image/png",
            size=len(content),
            width=width,
            height=height,
            created_at=now(),
        )
        db.add(asset)
    return asset


def wallet_for(db: Session, account: Account) -> Wallet:
    """Creates the wallet on first use with a recorded welcome grant and starter items."""
    wallet = db.get(Wallet, account.id)
    if wallet is not None:
        return wallet
    wallet = Wallet(account_id=account.id, gold=0, gem=0, updated_at=now())
    db.add(wallet)
    try:
        db.flush()
    except IntegrityError:
        db.rollback()
        return db.get(Wallet, account.id)
    for currency, amount in WELCOME.items():
        post_ledger(db, wallet, currency, amount, "welcome", f"welcome:{account.id}:{currency}")
    for item_id in STARTER_ITEMS:
        if db.get(InventoryItem, (account.id, item_id)) is None:
            db.add(InventoryItem(account_id=account.id, item_id=item_id))
    db.commit()
    return wallet


def post_ledger(
    db: Session,
    wallet: Wallet,
    currency: str,
    delta: int,
    kind: str,
    reference: str,
    *,
    item_id: str | None = None,
    amount_vnd: int | None = None,
    note: str = "",
    actor: str = "player",
) -> LedgerEntry:
    balance = getattr(wallet, currency) + delta
    if balance < 0:
        raise HTTPException(409, f"Not enough {currency}")
    setattr(wallet, currency, balance)
    wallet.updated_at = now()
    entry = LedgerEntry(
        account_id=wallet.account_id,
        currency=currency,
        delta=delta,
        balance_after=balance,
        kind=kind,
        reference=reference[:120],
        item_id=item_id,
        amount_vnd=amount_vnd,
        note=note[:300],
        actor=actor[:32],
        created_at=now(),
    )
    db.add(entry)
    return entry


def locked_wallet(db: Session, account: Account) -> Wallet:
    wallet_for(db, account)
    query = select(Wallet).where(Wallet.account_id == account.id)
    if db.bind.dialect.name == "postgresql":
        query = query.with_for_update()
    return db.scalar(query)


def already(db: Session, reference: str) -> LedgerEntry | None:
    return db.scalar(select(LedgerEntry).where(LedgerEntry.reference == reference))


def entry_view(entry: LedgerEntry) -> dict:
    return {
        "id": entry.id,
        "currency": entry.currency,
        "delta": entry.delta,
        "balance_after": entry.balance_after,
        "kind": entry.kind,
        "item_id": entry.item_id,
        "amount_vnd": entry.amount_vnd,
        "note": entry.note,
        "actor": entry.actor,
        "created_at": entry.created_at,
    }


def wallet_view(db: Session, account: Account) -> dict:
    wallet = wallet_for(db, account)
    stock = db.scalars(select(Stock).where(Stock.account_id == account.id, Stock.quantity > 0))
    items = db.scalars(select(InventoryItem.item_id).where(InventoryItem.account_id == account.id))
    return {
        "gold": wallet.gold,
        "gem": wallet.gem,
        "owned": list(items),
        "stock": {s.item_id: s.quantity for s in stock},
    }


@router.get("/wallet")
def my_wallet(account: Identity, db: Db):
    return wallet_view(db, account)


@router.get("/wallet/ledger")
def my_ledger(account: Identity, db: Db):
    rows = db.scalars(
        select(LedgerEntry)
        .where(LedgerEntry.account_id == account.id)
        .order_by(LedgerEntry.id.desc())
        .limit(100)
    )
    return {"entries": [entry_view(e) for e in rows]}


@router.get("/topup/packs")
def packs():
    return {
        "sandbox": True,
        "packs": [{"id": key, **value} for key, value in PACKS.items()],
    }


class Idempotent(BaseModel):
    # Client-generated once per tap; a retry with the same key is a no-op.
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9-]+$")


class TopupBody(Idempotent):
    pack_id: str


@router.post("/topup")
def topup(body: TopupBody, account: Identity, db: Db):
    pack = PACKS.get(body.pack_id)
    if pack is None:
        raise HTTPException(404, "Unknown pack")
    reference = f"topup:{account.id}:{body.request_id}"
    if already(db, reference) is None:
        wallet = locked_wallet(db, account)
        if "gem_cost" in pack:
            post_ledger(
                db,
                wallet,
                "gem",
                -pack["gem_cost"],
                "exchange",
                reference + ":gem",
                note=f"Đổi lấy {pack['name']}",
            )
            post_ledger(
                db, wallet, "gold", pack["amount"], "exchange", reference, note=pack["name"]
            )
        else:
            post_ledger(
                db,
                wallet,
                pack["currency"],
                pack["amount"],
                "topup",
                reference,
                amount_vnd=pack["vnd"],
                note=f"{pack['name']} (sandbox, không thu tiền)",
            )
        db.commit()
    return wallet_view(db, account)


class PurchaseBody(Idempotent):
    item_id: str = Field(min_length=1, max_length=64)


@router.post("/shop/purchase")
def purchase(body: PurchaseBody, account: Identity, db: Db):
    """Server-priced purchase: published catalog price, or the on-sale offer if cheaper."""
    from app.admin_api import ItemCatalog, ShopOffer, offer_view

    item = db.get(ItemCatalog, body.item_id)
    if item is None or item.status != "published":
        raise HTTPException(404, "Item not for sale")
    reference = f"buy:{account.id}:{body.request_id}"
    if already(db, reference) is not None:
        return wallet_view(db, account)
    price, currency = item.price, item.currency
    for offer in db.scalars(select(ShopOffer).where(ShopOffer.item_id == item.id)):
        view = offer_view(db, offer)
        if view["phase"] == "on_sale" and view["currency"] == currency:
            price = min(price, view["final_price"])
    consumable = item.category == "consumable"
    if not consumable and db.get(InventoryItem, (account.id, item.id)):
        raise HTTPException(409, "Already owned")
    wallet = locked_wallet(db, account)
    post_ledger(
        db, wallet, currency, -price, "purchase", reference, item_id=item.id, note=item.name
    )
    if consumable:
        stock = db.get(Stock, (account.id, item.id)) or Stock(
            account_id=account.id, item_id=item.id, quantity=0
        )
        stock.quantity += 1
        db.add(stock)
    else:
        db.add(InventoryItem(account_id=account.id, item_id=item.id))
    db.commit()
    return wallet_view(db, account)


def catalog_payload(db: Session) -> dict:
    from app.admin_api import ItemCatalog

    items = db.scalars(
        select(ItemCatalog).where(ItemCatalog.status == "published").order_by(ItemCatalog.id)
    )
    rows = [
        {
            "id": i.id,
            "name": i.name,
            "category": i.category,
            "rarity": i.rarity,
            "description": i.description,
            "price": i.price,
            "currency": i.currency,
            "duration_days": i.duration_days,
            "icon": i.icon,
            "icon_sha256": i.icon_sha256,
            "icon_url": f"/v1/assets/{i.icon_sha256}.png" if i.icon_sha256 else None,
        }
        for i in items
    ]
    version = hashlib.sha256(json.dumps(rows, sort_keys=True).encode()).hexdigest()[:16]
    return {"version": version, "items": rows}


@router.get("/catalog")
def catalog(
    db: Db,
    response: Response,
    if_none_match: Annotated[str | None, Header()] = None,
):
    """Public item list for clients. ETag lets clients skip unchanged downloads."""
    payload = catalog_payload(db)
    etag = f'"{payload["version"]}"'
    if if_none_match == etag:
        return Response(status_code=304, headers={"ETag": etag})
    response.headers["ETag"] = etag
    response.headers["Cache-Control"] = "no-cache"
    return payload


@router.get("/assets/{name}")
def asset(name: str, db: Db):
    digest = name.removesuffix(".png")
    if len(digest) != 64 or any(c not in "0123456789abcdef" for c in digest):
        raise HTTPException(404, "Asset not found")
    row = db.get(ItemAsset, digest)
    if row is None:
        raise HTTPException(404, "Asset not found")
    # Content-addressed: a changed icon gets a new URL, so this can be cached forever.
    return Response(
        content=row.content,
        media_type=row.content_type,
        headers={"Cache-Control": "public, max-age=31536000, immutable", "ETag": f'"{digest}"'},
    )
