"""Battle items: the six quick-slot consumables and the mount (docs/BATTLE_ITEMS.md).

Counts are the player's real stock (inventory_stock). Every use is recorded once in
``item_uses`` by its reference, so a retried report never consumes twice:
- online rounds: the arena reads the stock when a player sits down
  (GET /internal/v1/arena/loadout/{account}) and reports each use it accepted;
- practice rounds on the PC: the app reports each use (POST /v1/inventory/use).
"""

from datetime import UTC, datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import DateTime, ForeignKey, String, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.economy import Stock
from app.main import Account, Base, Db, Identity, InventoryItem
from app.matches import arena_service

router = APIRouter()

# Quick slots 1-6, in order. Effects and numbers live in the arena / practice rules.
SLOTS = ("throw_bomb", "dart", "blue_shield", "speed_shoes", "freeze_bomb", "push_glove")
PET_CATEGORY = "pet"
MAX_CARRIED = 99


def now() -> datetime:
    return datetime.now(UTC)


class ItemUse(Base):
    __tablename__ = "item_uses"
    reference: Mapped[str] = mapped_column(String(120), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    item_id: Mapped[str] = mapped_column(String(64))
    source: Mapped[str] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def loadout(db: Session, account_id: str) -> dict:
    """Counts per quick slot item (capped) and the pets the player owns.

    `pet` is the default (first owned); the arena may use another of `pets` when
    the client asks for the one it has equipped.
    """
    from app.admin_api import ItemCatalog

    stock = {
        s.item_id: s.quantity
        for s in db.scalars(
            select(Stock).where(Stock.account_id == account_id, Stock.item_id.in_(SLOTS))
        )
    }
    owned = list(
        db.scalars(select(InventoryItem.item_id).where(InventoryItem.account_id == account_id))
    )
    pets = [
        i
        for i in owned
        if (item := db.get(ItemCatalog, i)) is not None and item.category == PET_CATEGORY
    ]
    return {
        "slots": list(SLOTS),
        "items": {k: min(MAX_CARRIED, max(0, stock.get(k, 0))) for k in SLOTS},
        "pet": pets[0] if pets else None,
        "pets": pets,
    }


def consume(db: Session, account_id: str, item_id: str, reference: str, source: str) -> int:
    """Removes one use. Idempotent on `reference`; returns what is left."""
    stock = db.get(Stock, (account_id, item_id))
    if db.get(ItemUse, reference) is not None:
        return stock.quantity if stock else 0
    if stock is None or stock.quantity <= 0:
        raise HTTPException(409, "Item not in stock")
    stock.quantity -= 1
    db.add(
        ItemUse(
            reference=reference,
            account_id=account_id,
            item_id=item_id,
            source=source,
            created_at=now(),
        )
    )
    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        stock = db.get(Stock, (account_id, item_id))
    return stock.quantity if stock else 0


@router.get("/internal/v1/arena/loadout/{account_id}", dependencies=[Depends(arena_service)])
def arena_loadout(account_id: str, db: Db):
    """Arena only (service token): what a player brings into an online round."""
    if db.get(Account, account_id) is None:
        raise HTTPException(404, "Account not found")
    return loadout(db, account_id)


class UseBody(BaseModel):
    item_id: Literal[
        "throw_bomb", "dart", "blue_shield", "speed_shoes", "freeze_bomb", "push_glove"
    ]
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")


@router.get("/v1/inventory/loadout")
def my_loadout(account: Identity, db: Db):
    return loadout(db, account.id)


@router.post("/v1/inventory/use")
def use_item(body: UseBody, account: Identity, db: Db):
    """Practice rounds (client-run): one use of a quick slot item from the stock."""
    left = consume(
        db, account.id, body.item_id, f"practice:{account.id}:{body.request_id}", "practice"
    )
    return {"item_id": body.item_id, "left": left}
