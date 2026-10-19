"""Missions and LiveOps events (docs/LIVEOPS.md, spec BUPBUP_Mission_Event_LiveOps).

- Daily / weekly quests: rows in ``quest_definitions`` (admins edit them).
- Events: the ``events`` table (admin_api.GameEvent) plus a JSON ``config`` with
  chapters (story), event quests, the event token ("Vé Sao") and an Event Shop.
- Progress only comes from matches the server recorded (``matches.record_match``):
  verified online rounds, and practice rounds only when a quest objective allows
  the ``practice`` mode. Each (account, match) is processed once.
- Claims and shop orders are idempotent and run in one transaction.
"""

import uuid
from datetime import UTC, date, datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    func,
    select,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import Operator, Reader, audit
from app.economy import Stock, locked_wallet, post_ledger, wallet_view
from app.main import Account, Base, Db, Identity, InventoryItem

router = APIRouter()

# Vietnam has no daylight saving: days reset at 00:00 UTC+7, weeks on Monday.
TIMEZONE = "Asia/Ho_Chi_Minh"
VN = timezone(timedelta(hours=7))
RULES = (
    "MATCH_COMPLETED",
    "MATCH_WON",
    "BOMB_PLACED",
    "MAPS_DISTINCT",
    "LOGIN_DAY",
    "WITH_FRIEND",
    "BOSS_PLAYED",
    "BOSS_WON",
    "BOSS_DAMAGE",
    "BOSS_SUPPORT",
)
RULE_LABELS = {
    "MATCH_COMPLETED": "Hoàn thành trận",
    "MATCH_WON": "Thắng trận",
    "BOMB_PLACED": "Đặt bom nước",
    "MAPS_DISTINCT": "Chơi bản đồ khác nhau",
    "LOGIN_DAY": "Điểm danh ngày",
    "WITH_FRIEND": "Chơi cùng bạn bè",
    "BOSS_PLAYED": "Hoàn thành trận Boss",
    "BOSS_WON": "Đánh bại Boss",
    "BOSS_DAMAGE": "Gây sát thương lên Boss",
    "BOSS_SUPPORT": "Hành động hỗ trợ trong trận Boss",
}
# Boss raid objectives (docs/BOSS.md) count only valid boss raids, whatever `modes` says.
BOSS_RULES = ("BOSS_PLAYED", "BOSS_WON", "BOSS_DAMAGE", "BOSS_SUPPORT")
# Anti-farm for client-reported practice rounds (only counted where allowed).
PRACTICE_MIN_MS = 20_000
PRACTICE_PER_DAY = 40


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime | None) -> datetime | None:
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


def vn_day(at: datetime) -> date:
    return at.astimezone(VN).date()


def next_midnight(at: datetime) -> datetime:
    day = vn_day(at) + timedelta(days=1)
    return datetime(day.year, day.month, day.day, tzinfo=VN).astimezone(UTC)


def next_monday(at: datetime) -> datetime:
    day = vn_day(at)
    day += timedelta(days=7 - day.weekday())
    return datetime(day.year, day.month, day.day, tzinfo=VN).astimezone(UTC)


def week_key(at: datetime) -> str:
    year, week, _ = vn_day(at).isocalendar()
    return f"{year}-W{week:02d}"


# ---------------------------------------------------------------- models


class Objective(BaseModel):
    type: Literal[
        "MATCH_COMPLETED",
        "MATCH_WON",
        "BOMB_PLACED",
        "MAPS_DISTINCT",
        "LOGIN_DAY",
        "WITH_FRIEND",
        "BOSS_PLAYED",
        "BOSS_WON",
        "BOSS_DAMAGE",
        "BOSS_SUPPORT",
    ]
    target: int = Field(ge=1, le=1_000_000)
    # Empty = any map. Ids are map ids (park, moon, admin maps), never display names.
    map_ids: list[str] = Field(default_factory=list, max_length=20)
    # online = arena rounds (verified); practice = bot rounds the PC app reports.
    modes: list[Literal["online", "practice"]] = Field(default=["online"], min_length=1)


class Reward(BaseModel):
    type: Literal["gold", "gem", "token", "item"]
    amount: int = Field(default=1, ge=1, le=100_000)
    item_id: str | None = Field(default=None, max_length=64)


class QuestFields(BaseModel):
    title: str = Field(min_length=2, max_length=80)
    description: str = Field(default="", max_length=200)
    objectives: list[Objective] = Field(min_length=1, max_length=4)
    rewards: list[Reward] = Field(min_length=1, max_length=5)


class QuestBody(QuestFields):
    key: str = Field(pattern=r"^[A-Za-z0-9_]{2,32}$")
    scope: Literal["daily", "weekly"]
    sort: int = Field(default=0, ge=0, le=999)
    enabled: bool = True


class EventQuest(QuestFields):
    key: str = Field(pattern=r"^[A-Za-z0-9_]{2,32}$")
    chapter: str | None = None
    # once = one claim for the whole event; daily / weekly reset (Vietnam time).
    reset: Literal["once", "daily", "weekly"] = "once"


class Chapter(BaseModel):
    key: str = Field(pattern=r"^[A-Za-z0-9_]{2,32}$")
    title: str = Field(min_length=2, max_length=80)
    map_id: str | None = Field(default=None, max_length=24)
    unlock_offset_days: int = Field(default=0, ge=0, le=60)
    requires_previous: bool = True
    npc: str = Field(default="", max_length=40)
    npc_line: str = Field(default="", max_length=300)


class ShopEntry(BaseModel):
    sku: str = Field(pattern=r"^[A-Za-z0-9_]{2,32}$")
    item_id: str = Field(max_length=64)
    cost: int = Field(ge=1, le=100_000)
    stock: int | None = Field(default=None, ge=1, le=1_000_000)
    per_player: int = Field(default=1, ge=1, le=99)


BOSS_SKILLS = (
    "boss_basic_hit",
    "boss_aoe_mark",
    "boss_block_lane",
    "boss_wave_push",
    "boss_weak_point",
)
BOSS_ITEMS = ("throw_bomb", "dart", "blue_shield", "speed_shoes", "freeze_bomb", "push_glove")


class BossSession(BaseModel):
    """A daily play window in Vietnam time, e.g. 19:00-22:00 on chosen weekdays."""

    days_of_week: list[int] = Field(default=[1, 2, 3, 4, 5, 6, 7], min_length=1, max_length=7)
    local_start: str = Field(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")
    local_end: str = Field(pattern=r"^([01]\d|2[0-3]):[0-5]\d$|^24:00$")


class BossEligibility(BaseModel):
    """Who earns raid rewards (anti-AFK); spec defaults."""

    min_active_seconds: int = Field(default=45, ge=0, le=900)
    min_active_fraction: float = Field(default=0.5, ge=0, le=1)
    min_damage_fraction: float = Field(default=0.01, ge=0, le=1)
    support_actions: int = Field(default=3, ge=0, le=100)
    # Fewer accepted inputs than this during the raid = AFK.
    min_actions: int = Field(default=10, ge=0, le=1000)


class BossRules(BaseModel):
    """Boss raid of an event (docs/BOSS.md). The arena reads it; clients never send it."""

    boss_id: str = Field(default="boss_001", pattern=r"^[a-z0-9_]{2,32}$")
    asset_pack_id: str = Field(default="boss_001_placeholder", pattern=r"^[a-z0-9_]{2,48}$")
    display_name: str = Field(default="Boss Sự Kiện", min_length=2, max_length=40)
    map_id: str = Field(default="harbor", max_length=24)
    difficulty: Literal["EASY", "NORMAL", "HARD"] = "NORMAL"
    base_hp: int = Field(default=1000, ge=50, le=1_000_000)
    hp_per_extra_player: float = Field(default=0.55, ge=0, le=5)
    phase_thresholds: list[float] = Field(default=[0.7, 0.35], max_length=4)
    skills: list[Literal[BOSS_SKILLS]] = Field(default=list(BOSS_SKILLS), min_length=1)
    bomb_damage: int = Field(default=50, ge=1, le=10_000)
    weak_multiplier: float = Field(default=1.5, ge=1, le=5)
    min_players: int = Field(default=1, ge=1, le=8)
    max_players: int = Field(default=8, ge=1, le=8)
    duration_seconds: int = Field(default=300, ge=30, le=1800)
    items: list[Literal[BOSS_ITEMS]] = Field(default=list(BOSS_ITEMS))
    mount: bool = True
    reward_private_room: bool = False
    # Empty = playable for the whole event window.
    sessions: list[BossSession] = Field(default_factory=list, max_length=7)
    eligibility: BossEligibility = Field(default_factory=BossEligibility)
    full_reward_limit_per_day: int = Field(default=3, ge=0, le=100)
    win_rewards: list[Reward] = Field(
        default_factory=lambda: [
            Reward(type="gold", amount=150),
            Reward(type="token", amount=30),
        ],
        max_length=5,
    )
    lose_rewards: list[Reward] = Field(
        default_factory=lambda: [Reward(type="gold", amount=20)], max_length=5
    )


class EventConfig(BaseModel):
    token_name: str = Field(default="Vé Sao", max_length=24)
    banner: str = Field(default="", max_length=120)
    intro: str = Field(default="", max_length=400)
    npc: str = Field(default="", max_length=40)
    chapters: list[Chapter] = Field(default_factory=list, max_length=12)
    quests: list[EventQuest] = Field(default_factory=list, max_length=40)
    shop: list[ShopEntry] = Field(default_factory=list, max_length=20)
    # Boss raid (event kind "boss"); token_name is then the Boss Badge.
    boss: BossRules | None = None


class QuestDefinition(Base):
    __tablename__ = "quest_definitions"
    key: Mapped[str] = mapped_column(String(32), primary_key=True)
    scope: Mapped[str] = mapped_column(String(8))
    title: Mapped[str] = mapped_column(String(80))
    description: Mapped[str] = mapped_column(String(200), default="")
    objectives: Mapped[list] = mapped_column(JSON)
    rewards: Mapped[list] = mapped_column(JSON)
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    sort: Mapped[int] = mapped_column(Integer, default=0)
    updated_by: Mapped[str] = mapped_column(String(32), default="system")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class QuestProgress(Base):
    __tablename__ = "quest_progress"
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    quest_key: Mapped[str] = mapped_column(String(80), primary_key=True)
    period_key: Mapped[str] = mapped_column(String(16), primary_key=True)
    # One entry per objective: {"count": n, "seen": [...]} (seen = maps or days).
    state: Mapped[list] = mapped_column(JSON)
    status: Mapped[str] = mapped_column(String(12), default="in_progress")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class QuestMatchLog(Base):
    """Each verified (or allowed practice) match counts once per account."""

    __tablename__ = "quest_match_log"
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    match_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    source: Mapped[str] = mapped_column(String(10))
    day: Mapped[str] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class RewardClaim(Base):
    __tablename__ = "reward_claims"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    # account:quest:period — unique, so two devices claiming at once grant once.
    grant_key: Mapped[str] = mapped_column(String(140), unique=True)
    quest_key: Mapped[str] = mapped_column(String(80))
    event_id: Mapped[str | None] = mapped_column(String(36))
    rewards: Mapped[list] = mapped_column(JSON)
    claimed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class EventWallet(Base):
    __tablename__ = "event_wallets"
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    event_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    balance: Mapped[int] = mapped_column(Integer, default=0)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class EventTokenLedger(Base):
    __tablename__ = "event_token_ledger"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    event_id: Mapped[str] = mapped_column(String(36))
    delta: Mapped[int] = mapped_column(Integer)
    balance_after: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(12))
    reference: Mapped[str] = mapped_column(String(140), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class EventShopOrder(Base):
    __tablename__ = "event_shop_orders"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    event_id: Mapped[str] = mapped_column(String(36))
    sku: Mapped[str] = mapped_column(String(32))
    item_id: Mapped[str] = mapped_column(String(64))
    cost: Mapped[int] = mapped_column(Integer)
    reference: Mapped[str] = mapped_column(String(140), unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class EventVersion(Base):
    """Immutable snapshot written on every publish/resume."""

    __tablename__ = "event_versions"
    event_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, primary_key=True)
    snapshot: Mapped[dict] = mapped_column(JSON)
    created_by: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


# ---------------------------------------------------------------- defaults

DEFAULT_QUESTS: list[dict] = [
    {
        "key": "D01",
        "scope": "daily",
        "sort": 1,
        "title": "Điểm danh vui vẻ",
        "description": "Vào game lần đầu trong ngày",
        "objectives": [{"type": "LOGIN_DAY", "target": 1}],
        "rewards": [{"type": "gold", "amount": 100}],
    },
    {
        "key": "D02",
        "scope": "daily",
        "sort": 2,
        "title": "Khởi động trận đấu",
        "description": "Hoàn thành 2 trận hợp lệ",
        "objectives": [{"type": "MATCH_COMPLETED", "target": 2}],
        "rewards": [{"type": "gold", "amount": 150}],
    },
    {
        "key": "D03",
        "scope": "daily",
        "sort": 3,
        "title": "Cao thủ bóng nước",
        "description": "Thắng 1 trận",
        "objectives": [{"type": "MATCH_WON", "target": 1}],
        "rewards": [{"type": "gold", "amount": 200}],
    },
    {
        "key": "D04",
        "scope": "daily",
        "sort": 4,
        "title": "Nhà thám hiểm",
        "description": "Chơi trên 2 bản đồ khác nhau",
        "objectives": [{"type": "MAPS_DISTINCT", "target": 2}],
        "rewards": [{"type": "gold", "amount": 150}],
    },
    {
        "key": "D05",
        "scope": "daily",
        "sort": 5,
        "title": "Hội bạn thân thiết",
        "description": "Hoàn thành 1 trận cùng bạn bè (thưởng thêm)",
        "objectives": [{"type": "WITH_FRIEND", "target": 1}],
        "rewards": [{"type": "gold", "amount": 200}],
    },
    {
        "key": "W01",
        "scope": "weekly",
        "sort": 1,
        "title": "Chiến binh bền bỉ",
        "description": "Hoàn thành 15 trận hợp lệ trong tuần",
        "objectives": [{"type": "MATCH_COMPLETED", "target": 15}],
        "rewards": [{"type": "gold", "amount": 500}],
    },
    {
        "key": "W02",
        "scope": "weekly",
        "sort": 2,
        "title": "Du hành khắp nơi",
        "description": "Chơi ít nhất 5 bản đồ khác nhau",
        "objectives": [{"type": "MAPS_DISTINCT", "target": 5}],
        "rewards": [{"type": "gold", "amount": 300}],
    },
    {
        "key": "W03",
        "scope": "weekly",
        "sort": 3,
        "title": "Nhà vô địch tuần",
        "description": "Thắng 10 trận hợp lệ",
        "objectives": [{"type": "MATCH_WON", "target": 10}],
        "rewards": [{"type": "gold", "amount": 600}],
    },
]


def seed_defaults(db: Session) -> int:
    """Adds the spec's D01–D05 / W01–W03 quests that are missing (never overwrites)."""
    added = 0
    for data in DEFAULT_QUESTS:
        if db.get(QuestDefinition, data["key"]) is None:
            body = QuestBody(**data)
            db.add(definition_row(body, "system"))
            added += 1
    db.commit()
    return added


def template_boss_event() -> dict:
    """Boss raid event of the Boss Event spec (sample numbers, still to be approved)."""
    start = datetime.combine(vn_day(now()), datetime.min.time(), tzinfo=VN)

    def quest(key, title, reset, rule, target, rewards):
        return {
            "key": key,
            "title": title,
            "reset": reset,
            "objectives": [{"type": rule, "target": target}],
            "rewards": rewards,
        }

    def tokens(n):
        return [{"type": "token", "amount": n}]

    return {
        "name": "Đại Chiến Boss - Săn Boss Nhận Quà",
        "kind": "boss",
        "description": "Cả đội 1-8 người hạ Boss Sự Kiện ở Bến Cảng Bong Bóng.",
        "start_at": start.astimezone(UTC).isoformat(),
        "end_at": (start + timedelta(days=7)).astimezone(UTC).isoformat(),
        "claim_end_at": (start + timedelta(days=10)).astimezone(UTC).isoformat(),
        "reward_items": [],
        "config": {
            "token_name": "Huy Hiệu Boss",
            "banner": "Một sinh vật bí ẩn làm xáo trộn sức mạnh bóng nước!",
            "intro": (
                "Lập đội săn Boss, né các ô cảnh báo và đặt bom trúng Boss để khôi phục "
                "sự cân bằng của các vùng đất BỤP BỤP!. Tên và hình Boss sẽ cập nhật sau."
            ),
            "npc": "Boss Sự Kiện",
            "chapters": [],
            "boss": {
                "sessions": [
                    {
                        "days_of_week": [1, 2, 3, 4, 5, 6, 7],
                        "local_start": "19:00",
                        "local_end": "22:00",
                    }
                ]
            },
            "quests": [
                quest(
                    "BOSS_DAILY_PLAY_1",
                    "Hoàn thành 1 trận Boss hợp lệ",
                    "daily",
                    "BOSS_PLAYED",
                    1,
                    [{"type": "gold", "amount": 100}],
                ),
                quest(
                    "BOSS_DAILY_WIN_1", "Đánh bại Boss 1 lần", "daily", "BOSS_WON", 1, tokens(10)
                ),
                quest(
                    "BOSS_WEEKLY_WIN_5", "Thắng Boss 5 lần", "weekly", "BOSS_WON", 5, tokens(100)
                ),
                quest("BOSS_WIN_1", "Mốc 1 trận thắng", "once", "BOSS_WON", 1, tokens(20)),
                quest("BOSS_WIN_3", "Mốc 3 trận thắng", "once", "BOSS_WON", 3, tokens(30)),
                quest("BOSS_WIN_5", "Mốc 5 trận thắng", "once", "BOSS_WON", 5, tokens(50)),
                quest(
                    "BOSS_EVENT_CLEAR_10",
                    "Thắng Boss 10 lần trong mùa",
                    "once",
                    "BOSS_WON",
                    10,
                    [{"type": "item", "item_id": "effect_star", "amount": 1}],
                ),
                quest(
                    "BOSS_EVENT_CLEAR_20",
                    "Thắng Boss 20 lần trong mùa",
                    "once",
                    "BOSS_WON",
                    20,
                    [{"type": "item", "item_id": "wings_golden_light", "amount": 1}],
                ),
            ],
            "shop": [
                {"sku": "boss_dragon", "item_id": "pet_dragon", "cost": 300, "per_player": 1},
                {"sku": "boss_fire", "item_id": "effect_fire", "cost": 150, "per_player": 1},
                {
                    "sku": "boss_shield",
                    "item_id": "blue_shield",
                    "cost": 20,
                    "per_player": 10,
                    "stock": 10000,
                },
            ],
        },
    }


def template_event() -> dict:
    """Sample STORY_ARC event from the spec, mapped to this game's real map/item ids."""
    start = datetime.combine(vn_day(now()), datetime.min.time(), tzinfo=VN)

    def quest(key, title, chapter, objectives, gold, tokens, reset="once"):
        rewards = [{"type": "token", "amount": tokens}]
        if gold:
            rewards.insert(0, {"type": "gold", "amount": gold})
        return {
            "key": key,
            "title": title,
            "chapter": chapter,
            "reset": reset,
            "objectives": objectives,
            "rewards": rewards,
        }

    def done(target, maps=(), won=False):
        rule = "MATCH_WON" if won else "MATCH_COMPLETED"
        return {"type": rule, "target": target, "map_ids": list(maps)}

    return {
        "name": "Giải Cứu Bầu Trời Bong Bóng",
        "kind": "story",
        "description": "Sự kiện cốt truyện 7 chương: khôi phục Mảnh Sao Cầu Vồng.",
        "start_at": start.astimezone(UTC).isoformat(),
        "end_at": (start + timedelta(days=10)).astimezone(UTC).isoformat(),
        "claim_end_at": (start + timedelta(days=13)).astimezone(UTC).isoformat(),
        "reward_items": [],
        "config": {
            "token_name": "Vé Sao",
            "banner": "Đồng Hồ Bong Bóng ngừng quay! Cùng Mimi thắp lại bầu trời.",
            "intro": (
                "Chiếc Đồng Hồ Bong Bóng trên bầu trời BỤP BỤP! ngừng hoạt động. Những sắc màu "
                "bị phân tán khắp các vùng đất. Mimi cùng bạn bè phải khôi phục các Mảnh Sao "
                "Cầu Vồng trước khi lễ hội kết thúc."
            ),
            "npc": "Mimi",
            "chapters": [
                {
                    "key": "CH01",
                    "title": "Bến Cảng Bong Bóng",
                    "map_id": "harbor",
                    "unlock_offset_days": 0,
                    "npc": "Mimi",
                    "npc_line": "Ôi không! Những bong bóng cầu vồng đang biến mất. "
                    "Cậu giúp tớ mang màu sắc quay lại nhé?",
                },
                {
                    "key": "CH02",
                    "title": "Tiệm Bánh Mây",
                    "map_id": "pastry",
                    "unlock_offset_days": 1,
                },
                {
                    "key": "CH03",
                    "title": "Lâu Đài Băng",
                    "map_id": "frost",
                    "unlock_offset_days": 2,
                },
                {
                    "key": "CH04",
                    "title": "Ga Tàu Cầu Vồng",
                    "map_id": "station",
                    "unlock_offset_days": 3,
                },
                {
                    "key": "CH05",
                    "title": "Tháp Đồng Hồ",
                    "map_id": "clock",
                    "unlock_offset_days": 4,
                },
                {"key": "CH06", "title": "Hành Trình Sắc Màu", "unlock_offset_days": 5},
                {
                    "key": "CH07",
                    "title": "Đại Lễ Hội",
                    "unlock_offset_days": 6,
                    "npc": "Người giữ tháp",
                    "npc_line": "Chỉ còn một tia sáng nữa thôi! Hãy cùng mọi người thắp lại "
                    "Đồng Hồ Bong Bóng!",
                },
            ],
            "quests": [
                quest(
                    "CH01",
                    "Hoàn thành 2 trận tại Bến Cảng Bong Bóng",
                    "CH01",
                    [done(2, ["harbor"])],
                    100,
                    20,
                ),
                quest(
                    "CH02",
                    "Đặt 15 bom nước",
                    "CH02",
                    [{"type": "BOMB_PLACED", "target": 15}],
                    150,
                    25,
                ),
                quest(
                    "CH03",
                    "Thắng 1 trận tại Lâu Đài Băng",
                    "CH03",
                    [done(1, ["frost"], won=True)],
                    150,
                    30,
                ),
                quest(
                    "CH04",
                    "Hoàn thành 3 trận và thắng ít nhất 1 trận",
                    "CH04",
                    [done(3), done(1, won=True)],
                    150,
                    35,
                ),
                quest(
                    "CH05",
                    "2 trận tại Tháp Đồng Hồ, thắng 1 trận tại đó",
                    "CH05",
                    [done(2, ["clock"]), done(1, ["clock"], won=True)],
                    200,
                    40,
                ),
                quest(
                    "CH06",
                    "Chơi trên 3 bản đồ khác nhau",
                    "CH06",
                    [{"type": "MAPS_DISTINCT", "target": 3}],
                    200,
                    40,
                ),
                quest(
                    "CH07",
                    "Hoàn thành 5 trận, thắng ít nhất 1 trận",
                    "CH07",
                    [done(5), done(1, won=True)],
                    300,
                    60,
                ),
                quest("EVD1", "Hoàn thành 2 trận hôm nay", None, [done(2)], 0, 15, "daily"),
                quest("EVD2", "Thắng 1 trận hôm nay", None, [done(1, won=True)], 0, 20, "daily"),
            ],
            "shop": [
                {"sku": "star_fx", "item_id": "effect_star", "cost": 120, "per_player": 1},
                {"sku": "bunny", "item_id": "pet_bunny", "cost": 200, "per_player": 1},
                {"sku": "mimi_suit", "item_id": "outfit_mimi", "cost": 300, "per_player": 1},
                {
                    "sku": "flame",
                    "item_id": "flame_boost",
                    "cost": 30,
                    "per_player": 5,
                    "stock": 5000,
                },
            ],
        },
    }


# ---------------------------------------------------------------- validation


def known_maps(db: Session) -> set[str]:
    from app.maps import BUILTIN_IDS, GameMap

    return set(BUILTIN_IDS) | set(db.scalars(select(GameMap.id)))


def check_rewards(db: Session, rewards: list[Reward], where: str, allow_token: bool) -> list[str]:
    from app.admin_api import ItemCatalog

    errors = []
    for reward in rewards:
        if reward.type == "token" and not allow_token:
            errors.append(f"{where}: Vé sự kiện chỉ dùng trong sự kiện")
        if reward.type == "item":
            item = db.get(ItemCatalog, reward.item_id or "")
            if item is None:
                errors.append(f"{where}: vật phẩm '{reward.item_id}' không tồn tại")
            elif item.status == "hidden":
                errors.append(f"{where}: vật phẩm '{reward.item_id}' đang ẩn")
    return errors


def check_objectives(objectives: list[Objective], maps: set[str], where: str) -> list[str]:
    errors = []
    for objective in objectives:
        unknown = [m for m in objective.map_ids if m not in maps]
        if unknown:
            errors.append(f"{where}: bản đồ không tồn tại {', '.join(unknown)}")
        if objective.type == "WITH_FRIEND" and objective.modes == ["practice"]:
            errors.append(f"{where}: chơi cùng bạn chỉ có ở trận online")
    return errors


def validate_quest(db: Session, body: QuestBody) -> list[str]:
    where = f"Nhiệm vụ {body.key}"
    return check_objectives(body.objectives, known_maps(db), where) + check_rewards(
        db, body.rewards, where, allow_token=False
    )


def validate_event(
    db: Session,
    config: EventConfig,
    start_at: datetime,
    end_at: datetime,
    claim_end_at: datetime | None,
) -> dict:
    """Errors block saving; warnings (economy, empty sections) are shown to the admin."""
    from app.admin_api import ItemCatalog

    errors: list[str] = []
    warnings: list[str] = []
    start, end = aware(start_at), aware(end_at)
    claim_end = aware(claim_end_at) or end
    if not start < end <= claim_end:
        errors.append("Lịch phải theo thứ tự: bắt đầu < kết thúc ≤ hạn nhận thưởng")
    maps = known_maps(db)
    days = max(1, (end - start).days + (1 if (end - start) % timedelta(days=1) else 0))
    chapter_keys = [c.key for c in config.chapters]
    if len(set(chapter_keys)) != len(chapter_keys):
        errors.append("Mã chương bị trùng")
    for chapter in config.chapters:
        if chapter.map_id and chapter.map_id not in maps:
            errors.append(f"Chương {chapter.key}: bản đồ '{chapter.map_id}' không tồn tại")
        if chapter.unlock_offset_days >= days:
            errors.append(f"Chương {chapter.key}: mở sau khi sự kiện đã kết thúc")
    quest_keys = [q.key for q in config.quests]
    if len(set(quest_keys)) != len(quest_keys):
        errors.append("Mã nhiệm vụ bị trùng")
    max_tokens = 0
    for quest in config.quests:
        where = f"Nhiệm vụ {quest.key}"
        if quest.chapter and quest.chapter not in chapter_keys:
            errors.append(f"{where}: chương '{quest.chapter}' không có")
        if quest.chapter and quest.reset != "once":
            errors.append(f"{where}: nhiệm vụ chương chỉ nhận một lần")
        errors += check_objectives(quest.objectives, maps, where)
        errors += check_rewards(db, quest.rewards, where, allow_token=True)
        tokens = sum(r.amount for r in quest.rewards if r.type == "token")
        repeats = {"daily": days, "weekly": (days + 6) // 7}.get(quest.reset, 1)
        max_tokens += tokens * repeats
        if config.boss is None and any(o.type in BOSS_RULES for o in quest.objectives):
            errors.append(f"{where}: mục tiêu Boss cần sự kiện có cấu hình Boss")
        if sum(r.amount for r in quest.rewards if r.type == "gem") > 500:
            warnings.append(f"{where}: thưởng kim cương lớn, cần người duyệt kinh tế xem lại")
    for chapter in config.chapters:
        if chapter.key not in {q.chapter for q in config.quests}:
            warnings.append(f"Chương {chapter.key} chưa có nhiệm vụ")
    skus = [s.sku for s in config.shop]
    if len(set(skus)) != len(skus):
        errors.append("Mã SKU trong shop bị trùng")
    for entry in config.shop:
        item = db.get(ItemCatalog, entry.item_id)
        if item is None:
            errors.append(f"Shop {entry.sku}: vật phẩm '{entry.item_id}' không tồn tại")
        elif item.status == "hidden":
            errors.append(f"Shop {entry.sku}: vật phẩm '{entry.item_id}' đang ẩn")
        elif item.category != "consumable" and entry.per_player > 1:
            errors.append(f"Shop {entry.sku}: vật phẩm sở hữu vĩnh viễn chỉ đổi 1 lần/người")
    if config.boss is not None:
        boss_errors, boss_warnings, boss_tokens = validate_boss(db, config.boss, maps, days)
        errors += boss_errors
        warnings += boss_warnings
        max_tokens += boss_tokens
    if config.shop:
        if not max_tokens:
            errors.append("Shop cần Vé, nhưng không nhiệm vụ nào thưởng Vé")
        elif min(s.cost for s in config.shop) > max_tokens:
            warnings.append(
                f"Người chơi tích cực kiếm tối đa {max_tokens} {config.token_name}, "
                "không đủ đổi món rẻ nhất"
            )
    if not config.quests:
        warnings.append("Sự kiện chưa có nhiệm vụ nào")
    return {"ok": not errors, "errors": errors, "warnings": warnings, "max_tokens": max_tokens}


def map_seats(db: Session, map_id: str) -> int:
    """Spawn points of a map: the arena gives every map (built-in or admin) 8."""
    return 8 if map_id in known_maps(db) else 0


def validate_boss(db: Session, boss: BossRules, maps: set[str], days: int):
    """Publish checks of the spec (section 11): map, seats, phases, skills, rewards."""
    errors: list[str] = []
    warnings: list[str] = []
    if boss.map_id not in maps:
        errors.append(f"Boss: bản đồ '{boss.map_id}' không tồn tại")
    elif map_seats(db, boss.map_id) < boss.max_players:
        errors.append(f"Boss: bản đồ '{boss.map_id}' không đủ {boss.max_players} điểm xuất phát")
    if not boss.min_players <= boss.max_players <= 8:
        errors.append("Boss: cần 1 ≤ số người tối thiểu ≤ tối đa ≤ 8")
    thresholds = boss.phase_thresholds
    if any(not 0 < t < 1 for t in thresholds) or thresholds != sorted(thresholds, reverse=True):
        errors.append("Boss: ngưỡng phase phải giảm dần trong khoảng (0, 1), ví dụ 0.70, 0.35")
    if len(set(thresholds)) != len(thresholds):
        errors.append("Boss: ngưỡng phase bị trùng")
    if len(set(boss.skills)) != len(boss.skills):
        errors.append("Boss: kỹ năng bị trùng")
    if not {"boss_basic_hit", "boss_aoe_mark"} & set(boss.skills):
        errors.append("Boss: cần ít nhất một đòn gây sát thương (Basic Hit hoặc AOE)")
    for session in boss.sessions:
        if any(d < 1 or d > 7 for d in session.days_of_week):
            errors.append("Boss: ngày trong tuần là 1 (thứ Hai) đến 7 (Chủ nhật)")
        if session.local_end <= session.local_start:
            errors.append(f"Boss: phiên {session.local_start}-{session.local_end} không hợp lệ")
    errors += check_rewards(db, boss.win_rewards, "Boss thắng", allow_token=True)
    errors += check_rewards(db, boss.lose_rewards, "Boss thua", allow_token=True)
    if boss.reward_private_room:
        warnings.append("Boss: phòng riêng nhận thưởng, cần luật chống cày (anti-abuse)")
    if sum(r.amount for r in boss.win_rewards if r.type == "gem") > 100:
        warnings.append("Boss: thưởng kim cương mỗi trận lớn, cần người duyệt kinh tế xem lại")
    hp8 = round(boss.base_hp * (1 + boss.hp_per_extra_player * 7))
    bombs = -(-hp8 // boss.bomb_damage)
    if bombs > boss.duration_seconds:
        warnings.append(f"Boss 8 người cần {bombs} quả bom trúng trong {boss.duration_seconds}s")
    per_day = boss.full_reward_limit_per_day
    tokens = sum(r.amount for r in boss.win_rewards if r.type == "token")
    return errors, warnings, tokens * per_day * days


# ---------------------------------------------------------------- quest engine


class Quest:
    """A quest as one player sees it right now (definition + schedule + period)."""

    def __init__(self, key, scope, data, period, resets_at, event=None, chapter=None):
        self.key = key
        self.scope = scope
        self.title = data["title"]
        self.description = data.get("description", "")
        self.objectives = [Objective(**o) for o in data["objectives"]]
        self.rewards = [Reward(**r) for r in data["rewards"]]
        self.period = period
        self.resets_at = resets_at
        self.event = event
        self.chapter = chapter


def event_quest_key(event_id: str, key: str) -> str:
    return f"ev.{event_id}.{key}"


def event_config(event) -> EventConfig:
    return EventConfig(**(event.config or {}))


def event_window(event, at: datetime) -> str:
    """progress (running), claim (ended, claim window open) or closed."""
    from app.admin_api import event_phase

    phase = event_phase(event)
    if phase == "running":
        return "progress"
    claim_end = aware(event.claim_end_at) or aware(event.end_at)
    if phase == "ended" and at < claim_end:
        return "claim"
    return "closed"


def visible_events(db: Session, at: datetime) -> list:
    from app.admin_api import GameEvent

    rows = db.scalars(select(GameEvent).where(GameEvent.status == "published"))
    return [e for e in rows if event_window(e, at) != "closed"]


def chapter_unlock_at(event, chapter: Chapter) -> datetime:
    start = aware(event.start_at).astimezone(VN)
    day = start.date() + timedelta(days=chapter.unlock_offset_days)
    unlock = datetime(day.year, day.month, day.day, tzinfo=VN).astimezone(UTC)
    return max(unlock, aware(event.start_at))


def quests_for(db: Session, at: datetime, events=None) -> list[Quest]:
    found: list[Quest] = []
    defs = db.scalars(
        select(QuestDefinition)
        .where(QuestDefinition.enabled.is_(True))
        .order_by(QuestDefinition.scope, QuestDefinition.sort)
    )
    for row in defs:
        data = {
            "title": row.title,
            "description": row.description,
            "objectives": row.objectives,
            "rewards": row.rewards,
        }
        if row.scope == "daily":
            found.append(Quest(row.key, "daily", data, vn_day(at).isoformat(), next_midnight(at)))
        else:
            found.append(Quest(row.key, "weekly", data, week_key(at), next_monday(at)))
    for event in visible_events(db, at) if events is None else events:
        config = event_config(event)
        chapters = {c.key: c for c in config.chapters}
        for quest in config.quests:
            period, resets = "event", aware(event.end_at)
            if quest.reset == "daily":
                period, resets = vn_day(at).isoformat(), min(next_midnight(at), resets)
            elif quest.reset == "weekly":
                period, resets = week_key(at), min(next_monday(at), resets)
            found.append(
                Quest(
                    event_quest_key(event.id, quest.key),
                    "story" if quest.chapter else "event",
                    quest.model_dump(),
                    period,
                    resets,
                    event,
                    chapters.get(quest.chapter) if quest.chapter else None,
                )
            )
    return found


def progress_row(db: Session, account_id: str, quest: Quest) -> QuestProgress | None:
    return db.get(QuestProgress, (account_id, quest.key, quest.period))


def chapter_states(db: Session, account_id: str, event, quests: list[Quest], at) -> dict:
    """locked / playable / cleared per chapter key (cleared = all its quests done)."""
    config = event_config(event)
    states: dict[str, str] = {}
    previous_cleared = True
    for chapter in config.chapters:
        mine = [
            q for q in quests if q.event is event and q.chapter and q.chapter.key == chapter.key
        ]
        done = all(
            (row := progress_row(db, account_id, q)) is not None
            and row.status in ("completed", "claimed")
            for q in mine
        )
        open_ = at >= chapter_unlock_at(event, chapter) and (
            previous_cleared or not chapter.requires_previous
        )
        states[chapter.key] = (
            "cleared" if open_ and done and mine else ("playable" if open_ else "locked")
        )
        previous_cleared = states[chapter.key] == "cleared"
    return states


def can_progress(db: Session, account_id: str, quest: Quest, at, states_cache: dict) -> bool:
    if quest.event is None:
        return True
    if event_window(quest.event, at) != "progress":
        return False
    if quest.chapter is None:
        return True
    if quest.event.id not in states_cache:
        states_cache[quest.event.id] = chapter_states(
            db, account_id, quest.event, quests_for(db, at, [quest.event]), at
        )
    return states_cache[quest.event.id].get(quest.chapter.key) == "playable"


def advance(
    db: Session, account_id: str, quest: Quest, facts: dict, at: datetime
) -> QuestProgress | None:
    """Applies one fact set (a match or a login) to a quest; returns the row if changed."""
    row = progress_row(db, account_id, quest)
    if row is not None and row.status != "in_progress":
        return None
    state = (
        [dict(s) for s in row.state]
        if row
        else [{"count": 0, "seen": []} for _ in quest.objectives]
    )
    changed = False
    for i, objective in enumerate(quest.objectives):
        boss = objective.type in BOSS_RULES
        if boss != (facts["mode"] == "boss"):
            continue
        if not boss and facts["mode"] not in objective.modes and objective.type != "LOGIN_DAY":
            continue
        if objective.map_ids and facts.get("map_id") not in objective.map_ids:
            continue
        entry = state[i]
        kind = objective.type
        if kind == "LOGIN_DAY" and facts.get("login_day"):
            if facts["login_day"] not in entry["seen"]:
                entry["seen"] = entry["seen"] + [facts["login_day"]]
                entry["count"] = len(entry["seen"])
                changed = True
        elif facts.get("match"):
            step = {
                "MATCH_COMPLETED": 1,
                "MATCH_WON": 1 if facts["won"] else 0,
                "BOMB_PLACED": facts.get("bombs", 0),
                "WITH_FRIEND": 1 if facts.get("with_friend") else 0,
                "BOSS_PLAYED": 1,
                "BOSS_WON": 1 if facts["won"] else 0,
                "BOSS_DAMAGE": facts.get("damage", 0),
                "BOSS_SUPPORT": facts.get("support", 0),
            }.get(kind, 0)
            if kind == "MAPS_DISTINCT" and facts.get("map_id"):
                if facts["map_id"] not in entry["seen"]:
                    entry["seen"] = entry["seen"] + [facts["map_id"]]
                    entry["count"] = len(entry["seen"])
                    changed = True
            elif step:
                entry["count"] = min(objective.target, entry["count"] + step)
                changed = True
    if not changed:
        return None
    if row is None:
        row = QuestProgress(
            account_id=account_id,
            quest_key=quest.key,
            period_key=quest.period,
            state=state,
            status="in_progress",
            updated_at=at,
        )
        db.add(row)
    row.state = state
    row.updated_at = at
    if all(s["count"] >= o.target for s, o in zip(state, quest.objectives, strict=True)):
        row.status = "completed"
        row.completed_at = at
    return row


def apply_facts(db: Session, account_id: str, facts: dict, at: datetime) -> int:
    changed = 0
    cache: dict = {}
    for quest in quests_for(db, at):
        if can_progress(db, account_id, quest, at, cache) and advance(
            db, account_id, quest, facts, at
        ):
            changed += 1
    return changed


def is_friend(db: Session, me: str, other: str) -> bool:
    from app.social import link, relation

    return relation(link(db, me, other), me) == "friend"


def on_match(db: Session, match, participants: list, source: str, practice=False) -> None:
    """Called once per new recorded match (matches.record_match).

    Arena rounds are "online", except rounds of a practice room with server bots;
    those and client-reported bot rounds count as "practice".
    """
    at = now()
    mode = "online" if source == "arena" and not practice else "practice"
    if mode == "practice" and match.duration_ms < PRACTICE_MIN_MS:
        return
    people = [p for p in participants if getattr(p, "account_id", None) and not p.is_bot]
    ids = [p.account_id for p in people]
    day = vn_day(at).isoformat()
    for person in people:
        account_id = person.account_id
        if db.get(Account, account_id) is None:
            continue
        if db.get(QuestMatchLog, (account_id, match.id)) is not None:
            continue
        if mode == "practice":
            today = db.scalar(
                select(func.count())
                .select_from(QuestMatchLog)
                .where(
                    QuestMatchLog.account_id == account_id,
                    QuestMatchLog.source == "practice",
                    QuestMatchLog.day == day,
                )
            )
            if today >= PRACTICE_PER_DAY:
                continue
        db.add(
            QuestMatchLog(
                account_id=account_id, match_id=match.id, source=mode, day=day, created_at=at
            )
        )
        facts = {
            "match": True,
            "mode": mode,
            "map_id": match.map_id or None,
            "won": bool(person.winner),
            "bombs": max(0, int(person.bombs or 0)),
            "with_friend": any(
                other != account_id and is_friend(db, account_id, other) for other in ids
            ),
        }
        apply_facts(db, account_id, facts, at)


def touch_login(db: Session, account: Account, at: datetime) -> None:
    apply_facts(db, account.id, {"mode": "online", "login_day": vn_day(at).isoformat()}, at)


# ---------------------------------------------------------------- rewards


def token_wallet(db: Session, account_id: str, event_id: str, lock: bool = False) -> EventWallet:
    query = select(EventWallet).where(
        EventWallet.account_id == account_id, EventWallet.event_id == event_id
    )
    if lock and db.bind.dialect.name == "postgresql":
        query = query.with_for_update()
    wallet = db.scalar(query)
    if wallet is None:
        wallet = EventWallet(account_id=account_id, event_id=event_id, balance=0, updated_at=now())
        db.add(wallet)
        db.flush()
    return wallet


def post_tokens(db: Session, wallet: EventWallet, delta: int, reason: str, reference: str) -> None:
    if wallet.balance + delta < 0:
        raise HTTPException(409, "Not enough event tokens")
    wallet.balance += delta
    wallet.updated_at = now()
    db.add(
        EventTokenLedger(
            account_id=wallet.account_id,
            event_id=wallet.event_id,
            delta=delta,
            balance_after=wallet.balance,
            reason=reason,
            reference=reference[:140],
            created_at=now(),
        )
    )


def grant_item(db: Session, account_id: str, item_id: str, amount: int) -> None:
    from app.admin_api import ItemCatalog

    item = db.get(ItemCatalog, item_id)
    if item is None:
        raise HTTPException(409, "Reward item no longer exists")
    if item.category == "consumable":
        stock = db.get(Stock, (account_id, item_id)) or Stock(
            account_id=account_id, item_id=item_id, quantity=0
        )
        stock.quantity += amount
        db.add(stock)
    elif db.get(InventoryItem, (account_id, item_id)) is None:
        db.add(InventoryItem(account_id=account_id, item_id=item_id))


def grant(db: Session, account: Account, rewards: list[Reward], event_id, reference: str) -> None:
    wallet = None
    for i, reward in enumerate(rewards):
        ref = f"{reference}:{i}"
        if reward.type in ("gold", "gem"):
            wallet = wallet or locked_wallet(db, account)
            post_ledger(db, wallet, reward.type, reward.amount, "quest", ref, note="Nhiệm vụ")
        elif reward.type == "token":
            post_tokens(
                db, token_wallet(db, account.id, event_id, lock=True), reward.amount, "quest", ref
            )
        else:
            grant_item(db, account.id, reward.item_id or "", reward.amount)


# ---------------------------------------------------------------- player API


def reward_view(reward: Reward, token_name: str = "Vé") -> dict:
    out = reward.model_dump()
    if reward.type == "token":
        out["label"] = token_name
    return out


def quest_view(db: Session, account_id: str, quest: Quest, at, window="progress") -> dict:
    row = progress_row(db, account_id, quest)
    state = row.state if row else [{"count": 0, "seen": []} for _ in quest.objectives]
    status = row.status if row else "in_progress"
    if status == "in_progress" and window == "claim":
        status = "expired"
    token_name = event_config(quest.event).token_name if quest.event else "Vé"
    return {
        "key": quest.key,
        "scope": quest.scope,
        "title": quest.title,
        "description": quest.description,
        "status": status,
        "period": quest.period,
        "resets_at": quest.resets_at,
        "objectives": [
            {
                **o.model_dump(),
                "label": RULE_LABELS[o.type],
                "progress": min(o.target, int(s.get("count", 0))),
            }
            for o, s in zip(quest.objectives, state, strict=True)
        ],
        "rewards": [reward_view(r, token_name) for r in quest.rewards],
    }


def shop_view(db: Session, account_id: str, event, config: EventConfig) -> list[dict]:
    from app.admin_api import ItemCatalog

    out = []
    for entry in config.shop:
        item = db.get(ItemCatalog, entry.item_id)
        mine = db.scalar(
            select(func.count())
            .select_from(EventShopOrder)
            .where(
                EventShopOrder.event_id == event.id,
                EventShopOrder.sku == entry.sku,
                EventShopOrder.account_id == account_id,
            )
        )
        sold = db.scalar(
            select(func.count())
            .select_from(EventShopOrder)
            .where(EventShopOrder.event_id == event.id, EventShopOrder.sku == entry.sku)
        )
        owned = (
            item is not None
            and item.category != "consumable"
            and (db.get(InventoryItem, (account_id, entry.item_id)) is not None)
        )
        out.append(
            {
                **entry.model_dump(),
                "name": item.name if item else entry.item_id,
                "icon": item.icon if item else None,
                "icon_sha256": item.icon_sha256 if item else None,
                "bought": mine,
                "left": None if entry.stock is None else max(0, entry.stock - sold),
                "owned": owned,
            }
        )
    return out


def event_player_view(db: Session, account_id: str, event, quests: list[Quest], at) -> dict:
    config = event_config(event)
    window = event_window(event, at)
    mine = [q for q in quests if q.event is event]
    states = chapter_states(db, account_id, event, mine, at)
    wallet = db.scalar(
        select(EventWallet).where(
            EventWallet.account_id == account_id, EventWallet.event_id == event.id
        )
    )
    chapters = []
    for chapter in config.chapters:
        chapter_quests = [q for q in mine if q.chapter and q.chapter.key == chapter.key]
        state = states.get(chapter.key, "locked")
        views = [quest_view(db, account_id, q, at, window) for q in chapter_quests]
        if state == "locked":
            for view in views:
                if view["status"] == "in_progress":
                    view["status"] = "locked"
        chapters.append(
            {
                **chapter.model_dump(),
                "state": state,
                "unlock_at": chapter_unlock_at(event, chapter),
                "quests": views,
            }
        )
    return {
        "id": event.id,
        "name": event.name,
        "kind": event.kind,
        "description": event.description,
        "window": window,
        "start_at": event.start_at,
        "end_at": event.end_at,
        "claim_end_at": event.claim_end_at or event.end_at,
        "token_name": config.token_name,
        "tokens": wallet.balance if wallet else 0,
        "banner": config.banner,
        "intro": config.intro,
        "npc": config.npc,
        "chapters": chapters,
        "quests": [quest_view(db, account_id, q, at, window) for q in mine if q.chapter is None],
        "shop": shop_view(db, account_id, event, config),
        "version": event.version,
    }


def find_quest(db: Session, account_id: str, quest_key: str, at) -> Quest:
    for quest in quests_for(db, at):
        if quest.key == quest_key:
            return quest
    raise HTTPException(404, "Quest not found")


class ClaimBody(BaseModel):
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")


@router.get("/v1/quests")
def my_quests(account: Identity, db: Db):
    """Everything the mission window needs, with the server clock for countdowns."""
    at = now()
    touch_login(db, account, at)
    db.commit()
    quests = quests_for(db, at)
    daily = [q for q in quests if q.scope == "daily"]
    weekly = [q for q in quests if q.scope == "weekly"]
    events = []
    seen: set[str] = set()
    for quest in quests:
        if quest.event is not None and quest.event.id not in seen:
            seen.add(quest.event.id)
            events.append(event_player_view(db, account.id, quest.event, quests, at))
    for event in visible_events(db, at):
        if event.id not in seen:
            events.append(event_player_view(db, account.id, event, quests, at))
    out = {
        "server_now": at,
        "timezone": TIMEZONE,
        "daily": {
            "resets_at": next_midnight(at),
            "quests": [quest_view(db, account.id, q, at) for q in daily],
        },
        "weekly": {
            "resets_at": next_monday(at),
            "quests": [quest_view(db, account.id, q, at) for q in weekly],
        },
        "events": events,
    }
    claimable = [v for v in out["daily"]["quests"] + out["weekly"]["quests"]]
    for event in events:
        claimable += event["quests"]
        for chapter in event["chapters"]:
            claimable += chapter["quests"]
    out["claimable"] = sum(1 for v in claimable if v["status"] == "completed")
    return out


@router.get("/v1/events/active")
def active_events(account: Identity, db: Db):
    at = now()
    quests = quests_for(db, at)
    return {
        "server_now": at,
        "events": [
            event_player_view(db, account.id, e, quests, at) for e in visible_events(db, at)
        ],
    }


@router.post("/v1/quests/{quest_key}/claim")
def claim(quest_key: str, body: ClaimBody, account: Identity, db: Db):
    at = now()
    quest = find_quest(db, account.id, quest_key, at)
    grant_key = f"{account.id}:{quest.key}:{quest.period}"
    existing = db.scalar(select(RewardClaim).where(RewardClaim.grant_key == grant_key))
    if existing is not None:
        return claim_result(db, account, quest, existing)
    if quest.event is not None and event_window(quest.event, at) == "closed":
        raise HTTPException(409, "Event closed")
    row = progress_row(db, account.id, quest)
    if row is None or row.status != "completed":
        raise HTTPException(409, "Quest not completed")
    record = RewardClaim(
        id=str(uuid.uuid4()),
        account_id=account.id,
        grant_key=grant_key,
        quest_key=quest.key,
        event_id=quest.event.id if quest.event else None,
        rewards=[r.model_dump() for r in quest.rewards],
        claimed_at=at,
    )
    try:
        db.add(record)
        db.flush()
        grant(db, account, quest.rewards, record.event_id, f"claim:{record.id}")
        row.status = "claimed"
        row.updated_at = at
        db.commit()
    except IntegrityError:
        # Another device claimed first: return that result, never a second grant.
        db.rollback()
        record = db.scalar(select(RewardClaim).where(RewardClaim.grant_key == grant_key))
        if record is None:
            raise
    return claim_result(db, account, quest, record)


def claim_result(db: Session, account: Account, quest: Quest, record: RewardClaim) -> dict:
    tokens = None
    if quest.event is not None:
        tokens = token_wallet(db, account.id, quest.event.id).balance
        db.commit()
    return {
        "quest_key": quest.key,
        "status": "claimed",
        "claim_id": record.id,
        "rewards": record.rewards,
        "wallet": wallet_view(db, account),
        "tokens": tokens,
    }


class OrderBody(ClaimBody):
    sku: str = Field(pattern=r"^[A-Za-z0-9_]{2,32}$")


@router.post("/v1/events/{event_id}/shop/orders", status_code=201)
def shop_order(event_id: str, body: OrderBody, account: Identity, db: Db):
    from app.admin_api import GameEvent, ItemCatalog

    at = now()
    reference = f"shop:{account.id}:{body.request_id}"
    done = db.scalar(select(EventShopOrder).where(EventShopOrder.reference == reference))
    event = db.get(GameEvent, event_id)
    if event is None or event.status != "published" or event_window(event, at) == "closed":
        raise HTTPException(404, "Event not found")
    if done is not None:
        return order_result(db, account, event, done)
    config = event_config(event)
    entry = next((s for s in config.shop if s.sku == body.sku), None)
    if entry is None:
        raise HTTPException(404, "Shop item not found")
    item = db.get(ItemCatalog, entry.item_id)
    if item is None or item.status == "hidden":
        raise HTTPException(409, "Item unavailable")
    # Lock the token wallet first: concurrent orders of one player queue here.
    wallet = token_wallet(db, account.id, event.id, lock=True)

    def count(*where) -> int:
        return db.scalar(select(func.count()).select_from(EventShopOrder).where(*where))

    if (
        count(
            EventShopOrder.event_id == event.id,
            EventShopOrder.sku == entry.sku,
            EventShopOrder.account_id == account.id,
        )
        >= entry.per_player
    ):
        raise HTTPException(409, "Purchase limit reached")
    if item.category != "consumable" and db.get(InventoryItem, (account.id, item.id)):
        raise HTTPException(409, "Already owned")
    if (
        entry.stock is not None
        and count(EventShopOrder.event_id == event.id, EventShopOrder.sku == entry.sku)
        >= entry.stock
    ):
        raise HTTPException(409, "Sold out")
    order = EventShopOrder(
        id=str(uuid.uuid4()),
        account_id=account.id,
        event_id=event.id,
        sku=entry.sku,
        item_id=entry.item_id,
        cost=entry.cost,
        reference=reference,
        created_at=at,
    )
    try:
        db.add(order)
        post_tokens(db, wallet, -entry.cost, "shop", f"order:{order.id}")
        grant_item(db, account.id, item.id, 1)
        db.commit()
    except IntegrityError:
        db.rollback()
        order = db.scalar(select(EventShopOrder).where(EventShopOrder.reference == reference))
        if order is None:
            raise
    return order_result(db, account, event, order)


def order_result(db: Session, account: Account, event, order: EventShopOrder) -> dict:
    return {
        "order_id": order.id,
        "sku": order.sku,
        "item_id": order.item_id,
        "cost": order.cost,
        "tokens": token_wallet(db, account.id, event.id).balance,
    }


# ---------------------------------------------------------------- admin API


def definition_row(body: QuestBody, actor: str) -> QuestDefinition:
    return QuestDefinition(
        key=body.key,
        scope=body.scope,
        title=body.title,
        description=body.description,
        objectives=[o.model_dump() for o in body.objectives],
        rewards=[r.model_dump() for r in body.rewards],
        enabled=body.enabled,
        sort=body.sort,
        updated_by=actor,
        updated_at=now(),
    )


def definition_view(row: QuestDefinition) -> dict:
    return {
        "key": row.key,
        "scope": row.scope,
        "title": row.title,
        "description": row.description,
        "objectives": row.objectives,
        "rewards": row.rewards,
        "enabled": row.enabled,
        "sort": row.sort,
        "updated_by": row.updated_by,
        "updated_at": row.updated_at,
    }


@router.get("/admin/v1/quests")
def admin_quests(_: Reader, db: Db):
    rows = db.scalars(select(QuestDefinition).order_by(QuestDefinition.scope, QuestDefinition.sort))
    return {
        "quests": [definition_view(r) for r in rows],
        "rules": [{"type": t, "label": RULE_LABELS[t]} for t in RULES],
    }


@router.post("/admin/v1/quests/seed")
def admin_seed(admin: Operator, db: Db):
    added = seed_defaults(db)
    audit(db, admin, "quest.seed", "quest", "defaults", added=added)
    db.commit()
    return {"added": added}


@router.put("/admin/v1/quests/{key}")
def admin_save_quest(key: str, body: QuestBody, admin: Operator, db: Db):
    """Create or replace a daily/weekly quest (progress of the current period is kept)."""
    if body.key != key:
        raise HTTPException(422, "Quest key cannot change")
    errors = validate_quest(db, body)
    if errors:
        raise HTTPException(422, {"errors": errors, "warnings": []})
    row = db.get(QuestDefinition, key)
    before = definition_view(row) if row else None
    if row is None:
        row = definition_row(body, admin.username)
        db.add(row)
    else:
        fresh = definition_row(body, admin.username)
        for field in ("scope", "title", "description", "objectives", "rewards", "enabled", "sort"):
            setattr(row, field, getattr(fresh, field))
        row.updated_by = admin.username
        row.updated_at = now()
    audit(db, admin, "quest.save", "quest", key, before=before, after=definition_view(row))
    db.commit()
    return definition_view(row)


class EventCheck(BaseModel):
    start_at: datetime
    end_at: datetime
    claim_end_at: datetime | None = None
    config: EventConfig = Field(default_factory=EventConfig)


@router.post("/admin/v1/events/validate")
def admin_validate_event(body: EventCheck, _: Reader, db: Db):
    return validate_event(db, body.config, body.start_at, body.end_at, body.claim_end_at)


@router.get("/admin/v1/events/template")
def admin_event_template(_: Reader, kind: Literal["story", "boss"] = "story"):
    return template_boss_event() if kind == "boss" else template_event()


@router.get("/admin/v1/events/{event_id}/analytics")
def admin_event_analytics(event_id: str, _: Reader, db: Db):
    from app.admin_api import get_event

    event = get_event(db, event_id)
    config = event_config(event)
    prefix = event_quest_key(event.id, "")
    rows = list(db.scalars(select(QuestProgress).where(QuestProgress.quest_key.like(prefix + "%"))))
    participants = {r.account_id for r in rows}
    per_quest = []
    for quest in config.quests:
        key = event_quest_key(event.id, quest.key)
        mine = [r for r in rows if r.quest_key == key]
        per_quest.append(
            {
                "key": quest.key,
                "title": quest.title,
                "chapter": quest.chapter,
                "started": len({r.account_id for r in mine}),
                "completed": len({r.account_id for r in mine if r.status != "in_progress"}),
                "claimed": len({r.account_id for r in mine if r.status == "claimed"}),
            }
        )
    tokens_granted = db.scalar(
        select(func.coalesce(func.sum(EventTokenLedger.delta), 0)).where(
            EventTokenLedger.event_id == event.id, EventTokenLedger.reason == "quest"
        )
    )
    orders = list(db.scalars(select(EventShopOrder).where(EventShopOrder.event_id == event.id)))
    return {
        "participants": len(participants),
        "quests": per_quest,
        "tokens_granted": int(tokens_granted or 0),
        "tokens_spent": sum(o.cost for o in orders),
        "orders": len(orders),
        "buyers": len({o.account_id for o in orders}),
        "by_sku": {s.sku: sum(1 for o in orders if o.sku == s.sku) for s in config.shop},
        "versions": [
            {"version": v.version, "created_by": v.created_by, "created_at": v.created_at}
            for v in db.scalars(
                select(EventVersion)
                .where(EventVersion.event_id == event.id)
                .order_by(EventVersion.version)
            )
        ],
    }


def snapshot(db: Session, event, actor: str) -> None:
    """Immutable copy of what players see, written on publish and on resume."""
    from app.admin_api import event_view

    event.version = (event.version or 0) + 1
    view = event_view(event)
    db.add(
        EventVersion(
            event_id=event.id,
            version=event.version,
            snapshot={
                k: (v.isoformat() if isinstance(v, datetime) else v) for k, v in view.items()
            },
            created_by=actor,
            created_at=now(),
        )
    )
