"""Character experience after matches (docs/PROGRESSION.md, spec "Match EXP v1.1").

EXP is its own currency: not gold, gems, badges, rank points or mission progress.
Only the server grants it, once per (match, player), when a verified match is stored:
- PvP: ``matches.record_match`` for arena rounds (practice rooms with bots get 0);
- Boss raids: ``boss.record_raid``.
Every award keeps the rule version, multiplier, daily factor and breakdown it was
settled with, so a later rule change never touches old matches.

Rules are versioned rows (draft -> published). The rule in force for a match is the
latest one published before the match started; with none published, DEFAULTS apply.
The level curve is part of the code (CURVE_VERSION) and is not edited by admins.
"""

import uuid
from datetime import UTC, datetime, timedelta
from fractions import Fraction
from math import ceil, floor
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Integer,
    String,
    UniqueConstraint,
    func,
    select,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import Operator, Owner, Reader, audit
from app.liveops import vn_day
from app.main import Account, Base, Db, Identity

router = APIRouter()

CURVE_VERSION = 1
LEVEL_CAP = 100
MULTIPLIERS = (1.0, 1.25, 1.5, 2.0)
PVP, BOSS = "PVP", "PVE_BOSS"

REASONS = {
    "ABORTED": "Trận bị hủy",
    "PRACTICE": "Trận luyện tập với bot",
    "PRIVATE_ROOM": "Phòng riêng",
    "NOT_ACTIVE": "Chưa tham gia đủ thời gian",
    "AFK": "Không hoạt động (AFK)",
    "NO_CONTRIBUTION": "Chưa đóng góp đủ",
    "NO_ACCOUNT": "Tài khoản không tồn tại",
}
LABELS = {
    "completion": "Hoàn thành trận",
    "win": "Thưởng chiến thắng",
    "draw": "Hòa",
    "lose": "Thưởng tham gia",
    "timeout": "Thưởng tham gia",
    "ko": "Hạ đối phương",
    "assist": "Hỗ trợ hạ đối phương",
    "hit": "Bom đánh trúng",
    "rescue": "Cứu đồng đội",
    "objective": "Mục tiêu bản đồ",
    "boss_win": "Thưởng tiêu diệt Boss",
    "boss_damage": "EXP sát thương Boss",
    "interrupt": "Ngắt chiêu Boss",
    "minion": "Hạ quái triệu hồi",
    "phase": "Tham gia phase",
    "boss_objective": "Mục tiêu phụ",
}


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime | None) -> datetime | None:
    if value is not None and value.tzinfo is None:
        return value.replace(tzinfo=UTC)
    return value


def round_half_up(value: Fraction) -> int:
    return floor(value + Fraction(1, 2))


def required_xp(level: int) -> int:
    """EXP from level L to L + 1 (curve v1): 100 + 40(L-1) + 10(L-1)^2."""
    n = max(1, level) - 1
    return 100 + 40 * n + 10 * n * n


# ---------------------------------------------------------------- rules


class Line(BaseModel):
    """EXP per counted action and how many count in one match."""

    xp: int = Field(ge=0, le=10_000)
    max: int = Field(ge=0, le=100)


class PvpEligibility(BaseModel):
    # Normal play: active >= min(seconds, ceil(fraction x match seconds)).
    min_active_seconds: int = Field(default=30, ge=0, le=600)
    min_active_fraction: float = Field(default=0.4, ge=0, le=1)
    # Knocked out early: still rewarded after this much real play.
    early_active_seconds: int = Field(default=10, ge=0, le=600)
    # Distinct activity groups (moving, a bomb that did something, a hit, an item).
    min_groups: int = Field(default=2, ge=0, le=4)


class PvpRules(BaseModel):
    completion: int = Field(default=50, ge=0, le=10_000)
    outcome: dict[Literal["WIN", "DRAW", "LOSE"], int] = Field(
        default_factory=lambda: {"WIN": 100, "DRAW": 50, "LOSE": 25}
    )
    lines: dict[Literal["ko", "assist", "hit", "rescue", "objective"], Line] = Field(
        default_factory=lambda: {
            "ko": Line(xp=40, max=5),
            "assist": Line(xp=20, max=5),
            "hit": Line(xp=8, max=5),
            "rescue": Line(xp=15, max=3),
            "objective": Line(xp=10, max=5),
        }
    )
    caps: dict[Literal["WIN", "DRAW", "LOSE"], int] = Field(
        default_factory=lambda: {"WIN": 450, "DRAW": 300, "LOSE": 250}
    )
    eligibility: PvpEligibility = Field(default_factory=PvpEligibility)


class DailyTier(BaseModel):
    """From the n-th valid boss match of the day (Asia/Ho_Chi_Minh), EXP x factor."""

    from_count: int = Field(ge=1, le=1000)
    factor: float = Field(ge=0, le=1)


class BossXpRules(BaseModel):
    completion: int = Field(default=50, ge=0, le=10_000)
    outcome: dict[Literal["WIN", "LOSE", "TIMEOUT"], int] = Field(
        default_factory=lambda: {"WIN": 150, "LOSE": 25, "TIMEOUT": 25}
    )
    # Up to this much for dealing 1/n of the boss HP (n = team at the start).
    damage: int = Field(default=120, ge=0, le=10_000)
    lines: dict[Literal["interrupt", "rescue", "minion", "phase", "objective"], Line] = Field(
        default_factory=lambda: {
            "interrupt": Line(xp=15, max=3),
            "rescue": Line(xp=20, max=3),
            "minion": Line(xp=10, max=4),
            "phase": Line(xp=10, max=3),
            "objective": Line(xp=15, max=3),
        }
    )
    caps: dict[Literal["WIN", "LOSE", "TIMEOUT"], int] = Field(
        default_factory=lambda: {"WIN": 500, "LOSE": 180, "TIMEOUT": 180}
    )
    reward_private: bool = False
    daily: list[DailyTier] = Field(
        default_factory=lambda: [
            DailyTier(from_count=1, factor=1.0),
            DailyTier(from_count=6, factor=0.5),
            DailyTier(from_count=11, factor=0.25),
        ],
        max_length=10,
    )


class Multiplier(BaseModel):
    """Double EXP and friends: applies to matches started inside the window."""

    name: str = Field(default="", max_length=60)
    start_at: datetime
    end_at: datetime
    multiplier: float
    modes: list[Literal["PVP", "PVE_BOSS"]] = Field(default_factory=lambda: [PVP, BOSS])

    @model_validator(mode="after")
    def check(self):
        if self.multiplier not in MULTIPLIERS:
            raise ValueError(f"multiplier must be one of {MULTIPLIERS}")
        if aware(self.end_at) <= aware(self.start_at):
            raise ValueError("end_at must be after start_at")
        return self


class XpConfig(BaseModel):
    pvp: PvpRules = Field(default_factory=PvpRules)
    boss: BossXpRules = Field(default_factory=BossXpRules)
    multipliers: list[Multiplier] = Field(default_factory=list, max_length=50)


DEFAULTS = XpConfig()


class XpRuleSet(Base):
    __tablename__ = "xp_rule_sets"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    version: Mapped[int] = mapped_column(Integer, unique=True)
    status: Mapped[str] = mapped_column(String(10), default="draft")  # draft | published
    note: Mapped[str] = mapped_column(String(300), default="")
    config: Mapped[dict] = mapped_column(JSON)
    created_by: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    published_by: Mapped[str | None] = mapped_column(String(32))
    published_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), index=True)


class PlayerProgression(Base):
    __tablename__ = "player_progression"
    account_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    level: Mapped[int] = mapped_column(Integer, default=1)
    xp_in_level: Mapped[int] = mapped_column(Integer, default=0)
    total_xp: Mapped[int] = mapped_column(Integer, default=0)
    curve_version: Mapped[int] = mapped_column(Integer, default=CURVE_VERSION)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class MatchXpAward(Base):
    __tablename__ = "match_xp_awards"
    __table_args__ = (UniqueConstraint("match_id", "account_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    match_id: Mapped[str] = mapped_column(String(120), index=True)
    account_id: Mapped[str] = mapped_column(String(36), index=True)
    mode: Mapped[str] = mapped_column(String(10))
    result: Mapped[str] = mapped_column(String(8))
    eligible: Mapped[bool] = mapped_column(Boolean, default=False)
    reason: Mapped[str] = mapped_column(String(16), default="")
    ruleset_id: Mapped[str] = mapped_column(String(36))
    ruleset_version: Mapped[int] = mapped_column(Integer)
    # Counted actions the server saw (after dedupe, before caps), for support and audit.
    stats: Mapped[dict] = mapped_column(JSON)
    # [{key, count, xp}] before the match cap.
    lines: Mapped[list] = mapped_column(JSON)
    raw_exp: Mapped[int] = mapped_column(Integer, default=0)
    cap: Mapped[int] = mapped_column(Integer, default=0)
    capped_base_exp: Mapped[int] = mapped_column(Integer, default=0)
    event_multiplier: Mapped[float] = mapped_column(default=1.0)
    daily_factor: Mapped[float] = mapped_column(default=1.0)
    awarded_exp: Mapped[int] = mapped_column(Integer, default=0)
    level_before: Mapped[int] = mapped_column(Integer, default=1)
    level_after: Mapped[int] = mapped_column(Integer, default=1)
    progress_before: Mapped[int] = mapped_column(Integer, default=0)
    progress_after: Mapped[int] = mapped_column(Integer, default=0)
    day: Mapped[str] = mapped_column(String(10), index=True)
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class XpLedger(Base):
    __tablename__ = "player_xp_ledger"
    __table_args__ = (UniqueConstraint("source_type", "source_id", "account_id"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(String(36), index=True)
    source_type: Mapped[str] = mapped_column(String(20))  # MATCH | MANUAL_ADJUSTMENT
    source_id: Mapped[str] = mapped_column(String(120))
    amount: Mapped[int] = mapped_column(Integer)
    total_after: Mapped[int] = mapped_column(Integer)
    reason: Mapped[str] = mapped_column(String(300), default="")
    created_by: Mapped[str] = mapped_column(String(32), default="system")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def rule_in_force(db: Session, at: datetime) -> tuple[str, int, XpConfig]:
    """(id, version, config) of the rule published last before `at`."""
    row = db.scalar(
        select(XpRuleSet)
        .where(XpRuleSet.status == "published", XpRuleSet.published_at <= at)
        .order_by(XpRuleSet.published_at.desc(), XpRuleSet.version.desc())
        .limit(1)
    )
    if row is None:
        return "default", 0, DEFAULTS
    return row.id, row.version, XpConfig.model_validate(row.config)


def event_multiplier(config: XpConfig, mode: str, at: datetime) -> float:
    """Highest multiplier running when the match started (they never stack)."""
    live = [
        m.multiplier
        for m in config.multipliers
        if mode in m.modes and aware(m.start_at) <= at < aware(m.end_at)
    ]
    return min(2.0, max(live, default=1.0))


def daily_factor(config: XpConfig, nth: int) -> float:
    factor = 1.0
    for tier in sorted(config.boss.daily, key=lambda t: t.from_count):
        if nth >= tier.from_count:
            factor = tier.factor
    return factor


# ---------------------------------------------------------------- calculator


def counted(lines: dict[str, Line], counts: dict[str, int]) -> list[dict]:
    out = []
    for key, line in lines.items():
        n = min(max(0, int(counts.get(key, 0))), line.max)
        if n and line.xp:
            out.append({"key": key, "count": n, "xp": n * line.xp})
    return out


def pvp_outcome(person) -> str:
    return "WIN" if person["winner"] else ("DRAW" if person["draw"] else "LOSE")


def pvp_eligibility(rules: PvpRules, person: dict, duration_ms: int) -> str:
    """'' when eligible, else a REASONS key (spec 2.2)."""
    rule = rules.eligibility
    active = person["active_ms"]
    if person["groups"] < rule.min_groups:
        return "AFK"
    need = min(rule.min_active_seconds, ceil(rule.min_active_fraction * duration_ms / 1000))
    if active >= 1000 * need:
        return ""
    # Knocked out very early, after really playing.
    if person["eliminated"] and active >= 1000 * rule.early_active_seconds:
        return ""
    return "NOT_ACTIVE"


def pvp_lines(rules: PvpRules, person: dict) -> tuple[str, list[dict], int]:
    """(outcome, lines, cap) for an eligible PvP player (spec section 3)."""
    outcome = pvp_outcome(person)
    lines = [{"key": "completion", "count": 1, "xp": rules.completion}]
    lines.append({"key": outcome.lower(), "count": 1, "xp": rules.outcome[outcome]})
    lines += counted(rules.lines, person)
    return outcome, [x for x in lines if x["xp"]], rules.caps[outcome]


def boss_damage_xp(rules: BossXpRules, damage: int, hp_max: int, team: int) -> int:
    """round_half_up(D x min(1, damage / hp_max x n)): 1/n of the HP earns it all."""
    if hp_max <= 0 or damage <= 0:
        return 0
    share = min(Fraction(1), Fraction(min(damage, hp_max), hp_max) * max(1, team))
    return round_half_up(rules.damage * share)


def boss_lines(rules: BossXpRules, result: str, person: dict, hp_max: int, team: int):
    lines = [{"key": "completion", "count": 1, "xp": rules.completion}]
    key = "boss_win" if result == "WIN" else result.lower()
    lines.append({"key": key, "count": 1, "xp": rules.outcome[result]})
    damage = boss_damage_xp(rules, person["damage"], hp_max, team)
    lines.append({"key": "boss_damage", "count": 1, "xp": damage})
    extra = counted(rules.lines, person)
    for line in extra:
        if line["key"] == "objective":
            line["key"] = "boss_objective"
    return [x for x in lines + extra if x["xp"]], rules.caps[result]


def boss_eligibility(event_rules, result: str, private: bool, duration_ms: int, person, hp_max):
    """Same participation bar as the boss rewards (Boss spec v1.0), but for every result."""
    if result == "ABORT":
        return "ABORTED"
    rule = event_rules.eligibility
    need_ms = 1000 * min(rule.min_active_seconds, rule.min_active_fraction * duration_ms / 1000)
    if person["active_ms"] < need_ms:
        return "NOT_ACTIVE"
    if person["actions"] < rule.min_actions:
        return "AFK"
    if person["damage"] < rule.min_damage_fraction * hp_max and (
        person["support"] < rule.support_actions
    ):
        return "NO_CONTRIBUTION"
    return ""


def final_exp(base: int, multiplier: float, factor: float) -> int:
    return round_half_up(base * Fraction(str(multiplier)) * Fraction(str(factor)))


# ---------------------------------------------------------------- grant


def locked_progress(db: Session, account_id: str) -> PlayerProgression:
    """The player's row, locked for this transaction (created on first EXP)."""
    query = (
        select(PlayerProgression)
        .where(PlayerProgression.account_id == account_id)
        .with_for_update()
    )
    row = db.scalar(query)
    if row is None:
        try:
            with db.begin_nested():
                db.add(
                    PlayerProgression(
                        account_id=account_id,
                        level=1,
                        xp_in_level=0,
                        total_xp=0,
                        curve_version=CURVE_VERSION,
                        updated_at=now(),
                    )
                )
        except IntegrityError:
            pass  # a concurrent grant created it first
        row = db.scalar(query)
    return row


def add_xp(row: PlayerProgression, amount: int) -> None:
    """Adds EXP and levels up as many times as it covers; at the cap only total grows."""
    row.total_xp += amount
    if row.level >= LEVEL_CAP:
        row.xp_in_level = 0
        return
    row.xp_in_level += amount
    while row.level < LEVEL_CAP and row.xp_in_level >= required_xp(row.level):
        row.xp_in_level -= required_xp(row.level)
        row.level += 1
    if row.level >= LEVEL_CAP:
        row.xp_in_level = 0


def credit(db: Session, account_id: str, amount: int, source_type: str, source_id: str, **ledger):
    """Locks progression, adds EXP and writes the ledger row (unique per source)."""
    row = locked_progress(db, account_id)
    before = (row.level, row.xp_in_level)
    if amount > 0:
        add_xp(row, amount)
        row.updated_at = now()
        db.add(
            XpLedger(
                id=str(uuid.uuid4()),
                account_id=account_id,
                source_type=source_type,
                source_id=source_id,
                amount=amount,
                total_after=row.total_xp,
                created_at=now(),
                **ledger,
            )
        )
    return row, before


def settle(
    db: Session,
    *,
    match_id: str,
    mode: str,
    started_at: datetime,
    people: list[dict],
    judge,
    lines_of,
) -> list[MatchXpAward]:
    """Stores one award per player once (QA: ten retries still give one award and ledger).

    `judge(person, config) -> reason` and `lines_of(person, config) -> (result, lines, cap)`.
    """
    started_at = aware(started_at)
    ruleset_id, version, config = rule_in_force(db, started_at)
    at = now()
    day = vn_day(at).isoformat()
    multiplier = event_multiplier(config, mode, started_at)
    out = []
    for person in people:
        account_id = person["account_id"]
        existing = db.scalar(
            select(MatchXpAward).where(
                MatchXpAward.match_id == match_id, MatchXpAward.account_id == account_id
            )
        )
        if existing is not None:
            out.append(existing)
            continue
        reason = "NO_ACCOUNT" if db.get(Account, account_id) is None else judge(person, config)
        result, lines, cap = lines_of(person, config)
        raw = sum(x["xp"] for x in lines)
        base = min(raw, cap)
        factor = 1.0
        if mode == BOSS and not reason:
            done = db.scalar(
                select(func.count())
                .select_from(MatchXpAward)
                .where(
                    MatchXpAward.account_id == account_id,
                    MatchXpAward.mode == BOSS,
                    MatchXpAward.eligible.is_(True),
                    MatchXpAward.day == day,
                )
            )
            factor = daily_factor(config, int(done or 0) + 1)
        amount = 0 if reason else final_exp(base, multiplier, factor)
        award = MatchXpAward(
            id=str(uuid.uuid4()),
            match_id=match_id,
            account_id=account_id,
            mode=mode,
            result=result,
            eligible=not reason,
            reason=reason,
            ruleset_id=ruleset_id,
            ruleset_version=version,
            stats={k: v for k, v in person.items() if k != "account_id"},
            lines=lines if not reason else [],
            raw_exp=raw if not reason else 0,
            cap=cap,
            capped_base_exp=base if not reason else 0,
            event_multiplier=multiplier,
            daily_factor=factor,
            awarded_exp=amount,
            day=day,
            started_at=started_at,
            created_at=at,
        )
        try:
            with db.begin_nested():
                db.add(award)
                db.flush()
                if reason == "NO_ACCOUNT":
                    award.level_before = award.level_after = 1
                else:
                    row, before = credit(db, account_id, amount, "MATCH", match_id)
                    award.level_before, award.progress_before = before
                    award.level_after, award.progress_after = row.level, row.xp_in_level
                db.flush()
        except IntegrityError:
            continue  # a concurrent worker settled this player first
        out.append(award)
    return out


def settle_pvp(db: Session, match_id: str, match, participants: list, practice: bool) -> None:
    """Called once per newly stored verified arena round (matches.record_match)."""
    duration = match.duration_ms
    people = []
    for p in participants:
        if p.is_bot or not p.account_id:
            continue
        people.append(
            {
                "account_id": p.account_id,
                "winner": p.winner,
                # No winner: whoever was still in at the end drew, the others lost.
                "draw": not match.winner_name and p.survived_ms >= duration,
                "eliminated": not p.winner and p.survived_ms < duration,
                "ko": p.kills,
                "assist": p.assists,
                "hit": p.hits,
                "rescue": p.rescues,
                "objective": p.objectives,
                "active_ms": p.active_ms,
                "groups": p.groups,
                "survived_ms": p.survived_ms,
            }
        )

    def judge(person, config):
        return "PRACTICE" if practice else pvp_eligibility(config.pvp, person, duration)

    settle(
        db,
        match_id=match_id,
        mode=PVP,
        started_at=match.started_at,
        people=people,
        judge=judge,
        lines_of=lambda person, config: pvp_lines(config.pvp, person),
    )


def settle_boss(db: Session, raid, raiders: list, event_rules, team: int) -> None:
    """Called once per newly stored boss raid (boss.record_raid)."""
    people = [
        {
            "account_id": r.account_id,
            "damage": r.damage,
            "support": r.support,
            "actions": r.actions,
            "active_ms": r.active_ms,
            "interrupt": r.interrupts,
            "rescue": r.rescues,
            "minion": r.minions,
            "phase": r.phases,
            "objective": r.objectives,
        }
        for r in raiders
    ]
    result = raid.result
    team = max(1, team or len(people))

    def judge(person, config):
        if raid.private and not config.boss.reward_private and result != "ABORT":
            return "PRIVATE_ROOM"
        return boss_eligibility(
            event_rules, result, raid.private, raid.duration_ms, person, raid.hp_max
        )

    def lines_of(person, config):
        if result == "ABORT":
            return result, [], 0
        lines, cap = boss_lines(config.boss, result, person, raid.hp_max, team)
        return result, lines, cap

    settle(
        db,
        match_id=raid.id,
        mode=BOSS,
        started_at=aware(raid.created_at) - timedelta(milliseconds=raid.duration_ms),
        people=people,
        judge=judge,
        lines_of=lines_of,
    )


# ---------------------------------------------------------------- player API


def progress_view(row: PlayerProgression | None) -> dict:
    level = row.level if row else 1
    return {
        "level": level,
        "xp_in_level": row.xp_in_level if row else 0,
        "total_xp": row.total_xp if row else 0,
        "next_level_required_exp": 0 if level >= LEVEL_CAP else required_xp(level),
        "max_level": level >= LEVEL_CAP,
        "level_cap": LEVEL_CAP,
        "curve_version": CURVE_VERSION,
    }


def award_view(award: MatchXpAward) -> dict:
    return {
        "match_id": award.match_id,
        "player_id": award.account_id,
        "mode": award.mode,
        "result": award.result,
        "eligible": award.eligible,
        "reason": award.reason,
        "reason_text": REASONS.get(award.reason, ""),
        "support_code": award.id[:8].upper(),
        "ruleset": {"id": award.ruleset_id, "version": award.ruleset_version},
        "breakdown": {x["key"]: x["xp"] for x in award.lines},
        "lines": [{**x, "label": LABELS.get(x["key"], x["key"])} for x in award.lines],
        "raw_exp": award.raw_exp,
        "cap": award.cap,
        "capped": award.raw_exp > award.capped_base_exp,
        "capped_base_exp": award.capped_base_exp,
        "event_multiplier": award.event_multiplier,
        "daily_factor": award.daily_factor,
        "awarded_exp": award.awarded_exp,
        "level_before": award.level_before,
        "level_after": award.level_after,
        "progress_before": award.progress_before,
        "progress_after": award.progress_after,
        "next_level_required_exp": (
            0 if award.level_after >= LEVEL_CAP else required_xp(award.level_after)
        ),
        "grant_status": "SETTLED",
        "created_at": award.created_at,
    }


@router.get("/v1/progression/me")
def my_progression(account: Identity, db: Db):
    return progress_view(db.get(PlayerProgression, account.id))


@router.get("/v1/progression/me/matches")
def my_awards(account: Identity, db: Db, limit: Annotated[int, Query(ge=1, le=50)] = 20):
    rows = db.scalars(
        select(MatchXpAward)
        .where(MatchXpAward.account_id == account.id)
        .order_by(MatchXpAward.created_at.desc())
        .limit(limit)
    )
    return {"awards": [award_view(a) for a in rows]}


@router.get("/v1/matches/{match_id}/exp")
def match_exp(match_id: str, account: Identity, db: Db):
    """This player's settled EXP for one match (404 until the arena's report is stored)."""
    award = db.scalar(
        select(MatchXpAward).where(
            MatchXpAward.match_id == match_id, MatchXpAward.account_id == account.id
        )
    )
    if award is None:
        raise HTTPException(404, "EXP not settled")
    return award_view(award)


# ---------------------------------------------------------------- admin API


def rule_view(row: XpRuleSet, active_id: str) -> dict:
    return {
        "id": row.id,
        "version": row.version,
        "status": row.status,
        "active": row.id == active_id,
        "note": row.note,
        "config": row.config,
        "created_by": row.created_by,
        "created_at": row.created_at,
        "published_by": row.published_by,
        "published_at": row.published_at,
    }


# The spec's sample players (section 3.1 and 4.2), for the preview.
SAMPLES = {
    "pvp_win": {"winner": True, "draw": False, "ko": 3, "assist": 2, "hit": 3, "rescue": 1},
    "pvp_lose": {"winner": False, "draw": False, "ko": 1, "hit": 1},
    "boss_win": {"result": "WIN", "damage": 900, "interrupt": 2, "rescue": 1, "phase": 3},
    "boss_lose": {"result": "LOSE", "damage": 200, "interrupt": 1, "phase": 2},
}


def preview(config: XpConfig) -> dict:
    out = {}
    for name, sample in SAMPLES.items():
        if name.startswith("pvp"):
            _, lines, cap = pvp_lines(config.pvp, sample)
        else:
            lines, cap = boss_lines(config.boss, sample["result"], sample, 2650, 4)
        raw = sum(x["xp"] for x in lines)
        out[name] = {"lines": lines, "raw": raw, "cap": cap, "base": min(raw, cap)}
    # Matches to go from level 1 to 10 / 20 at the PvP win and loss samples.
    for level in (10, 20):
        need = sum(required_xp(n) for n in range(1, level))
        out[f"matches_to_{level}"] = {
            k: ceil(need / out[k]["base"]) if out[k]["base"] else None
            for k in ("pvp_win", "pvp_lose")
        }
    return out


@router.get("/admin/v1/exp/rules")
def admin_rules(_: Reader, db: Db):
    active_id, active_version, active = rule_in_force(db, now())
    rows = db.scalars(select(XpRuleSet).order_by(XpRuleSet.version.desc()).limit(50))
    return {
        "active": {"id": active_id, "version": active_version, "config": active.model_dump()},
        "rules": [rule_view(r, active_id) for r in rows],
        "defaults": DEFAULTS.model_dump(),
        "preview": preview(active),
        "level_curve": {
            "version": CURVE_VERSION,
            "cap": LEVEL_CAP,
            "levels": [{"level": n, "required": required_xp(n)} for n in range(1, 31)],
        },
        "multipliers": list(MULTIPLIERS),
    }


class RuleBody(BaseModel):
    config: XpConfig
    note: str = Field(default="", max_length=300)


@router.post("/admin/v1/exp/rules/preview")
def admin_preview(body: RuleBody, _: Reader):
    return preview(body.config)


@router.post("/admin/v1/exp/rules", status_code=201)
def create_rule(body: RuleBody, admin: Operator, db: Db):
    """A new draft; it changes nothing until an owner publishes it."""
    version = int(db.scalar(select(func.max(XpRuleSet.version))) or 0) + 1
    row = XpRuleSet(
        id=str(uuid.uuid4()),
        version=version,
        status="draft",
        note=body.note,
        config=body.config.model_dump(mode="json"),
        created_by=admin.username,
        created_at=now(),
    )
    db.add(row)
    audit(db, admin, "exp.rule.create", "xp_rule", row.id, body.note, version=version)
    db.commit()
    return rule_view(row, "")


def draft(db: Session, rule_id: str) -> XpRuleSet:
    row = db.get(XpRuleSet, rule_id)
    if row is None:
        raise HTTPException(404, "Rule not found")
    if row.status != "draft":
        raise HTTPException(409, "Published rules cannot change; create a new draft")
    return row


@router.put("/admin/v1/exp/rules/{rule_id}")
def update_rule(rule_id: str, body: RuleBody, admin: Operator, db: Db):
    row = draft(db, rule_id)
    row.config = body.config.model_dump(mode="json")
    row.note = body.note
    audit(db, admin, "exp.rule.update", "xp_rule", row.id, body.note, version=row.version)
    db.commit()
    return rule_view(row, "")


@router.delete("/admin/v1/exp/rules/{rule_id}", status_code=204)
def delete_rule(rule_id: str, admin: Operator, db: Db):
    row = draft(db, rule_id)
    audit(db, admin, "exp.rule.delete", "xp_rule", row.id, version=row.version)
    db.delete(row)
    db.commit()


@router.post("/admin/v1/exp/rules/{rule_id}/publish")
def publish_rule(rule_id: str, admin: Owner, db: Db):
    """Applies to matches that start from now on; settled matches keep their rule."""
    row = draft(db, rule_id)
    row.status = "published"
    row.published_by = admin.username
    row.published_at = now()
    audit(db, admin, "exp.rule.publish", "xp_rule", row.id, version=row.version)
    db.commit()
    return rule_view(row, row.id)


@router.get("/admin/v1/exp/stats")
def admin_stats(_: Reader, db: Db, days: Annotated[int, Query(ge=1, le=60)] = 7):
    """EXP per day and mode, rejection reasons and the day's top earners (anomalies)."""
    first = (vn_day(now()) - timedelta(days=days - 1)).isoformat()
    rows = db.execute(
        select(
            MatchXpAward.day,
            MatchXpAward.mode,
            func.count(),
            func.sum(MatchXpAward.awarded_exp),
            func.count(func.distinct(MatchXpAward.account_id)),
            func.sum(MatchXpAward.eligible.cast(Integer)),
        )
        .where(MatchXpAward.day >= first)
        .group_by(MatchXpAward.day, MatchXpAward.mode)
        .order_by(MatchXpAward.day)
    ).all()
    reasons = db.execute(
        select(MatchXpAward.reason, func.count())
        .where(MatchXpAward.day >= first, MatchXpAward.reason != "")
        .group_by(MatchXpAward.reason)
    ).all()
    today = vn_day(now()).isoformat()
    top = db.execute(
        select(
            MatchXpAward.account_id,
            func.count(),
            func.sum(MatchXpAward.awarded_exp).label("exp"),
        )
        .where(MatchXpAward.day == today)
        .group_by(MatchXpAward.account_id)
        .order_by(func.sum(MatchXpAward.awarded_exp).desc())
        .limit(10)
    ).all()
    names = {
        a.id: a.display_name
        for a in db.scalars(select(Account).where(Account.id.in_([t[0] for t in top])))
    }
    return {
        "days": [
            {
                "day": d,
                "mode": m,
                "awards": n,
                "exp": int(total or 0),
                "players": players,
                "eligible": int(ok or 0),
                "exp_per_player": round(int(total or 0) / players) if players else 0,
            }
            for d, m, n, total, players, ok in rows
        ],
        "reasons": {r: n for r, n in reasons},
        "top_today": [
            {"account_id": a, "name": names.get(a, "?"), "matches": n, "exp": int(exp or 0)}
            for a, n, exp in top
        ],
    }


@router.get("/admin/v1/exp/players/{account_id}")
def admin_player(account_id: str, _: Reader, db: Db):
    if db.get(Account, account_id) is None:
        raise HTTPException(404, "Account not found")
    awards = db.scalars(
        select(MatchXpAward)
        .where(MatchXpAward.account_id == account_id)
        .order_by(MatchXpAward.created_at.desc())
        .limit(30)
    )
    ledger = db.scalars(
        select(XpLedger)
        .where(XpLedger.account_id == account_id)
        .order_by(XpLedger.created_at.desc())
        .limit(30)
    )
    return {
        "progression": progress_view(db.get(PlayerProgression, account_id)),
        "awards": [{**award_view(a), "stats": a.stats} for a in awards],
        "ledger": [
            {
                "source_type": e.source_type,
                "source_id": e.source_id,
                "amount": e.amount,
                "total_after": e.total_after,
                "reason": e.reason,
                "created_by": e.created_by,
                "created_at": e.created_at,
            }
            for e in ledger
        ],
    }


class AdjustBody(BaseModel):
    amount: int = Field(ge=1, le=100_000)
    reason: str = Field(min_length=5, max_length=300)
    request_id: str = Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_.:-]+$")


@router.post("/admin/v1/exp/players/{account_id}/adjust")
def admin_adjust(account_id: str, body: AdjustBody, admin: Owner, db: Db):
    """MANUAL_ADJUSTMENT: owners only, with a reason, audited, once per request id."""
    if db.get(Account, account_id) is None:
        raise HTTPException(404, "Account not found")
    exists = db.scalar(
        select(XpLedger).where(
            XpLedger.source_type == "MANUAL_ADJUSTMENT",
            XpLedger.source_id == body.request_id,
            XpLedger.account_id == account_id,
        )
    )
    if exists is None:
        credit(
            db,
            account_id,
            body.amount,
            "MANUAL_ADJUSTMENT",
            body.request_id,
            reason=body.reason,
            created_by=admin.username,
        )
        audit(db, admin, "exp.adjust", "account", account_id, body.reason, amount=body.amount)
        db.commit()
    return {
        "already": exists is not None,
        "progression": progress_view(db.get(PlayerProgression, account_id)),
    }
