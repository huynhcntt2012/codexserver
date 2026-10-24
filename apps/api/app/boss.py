"""Boss raids (docs/BOSS.md, spec "BUPBUP Boss Event Dev Package").

A boss event is a LiveOps event (``events`` row, kind "boss") whose JSON config
has a ``boss`` block (liveops.BossRules). The badge is the event token, Boss
quests are event quests with BOSS_* objectives, the Event Shop is the event shop.
This module adds what is specific to raids:

- ``GET /internal/v1/boss/events/{id}``: rules for the arena and whether a new
  raid may start now (published, running, inside a session, not switched off).
- ``boss_raid`` ingest (from matches.arena_event): one row per raid, idempotent
  on the arena's match id; eligibility per raider; reward grants; quest progress.
- Player API: active boss events, raid result, pending rewards, idempotent claim.
- Admin API: raids, analytics, settle (expire unclaimed rewards after the claim
  window). Publish / pause / versions / audit are the normal event endpoints.

The arena is the authority for HP, damage and the result; nothing here trusts a
client. Rewards are granted only on claim, in one transaction, once per grant.
"""

import os
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Integer,
    String,
    UniqueConstraint,
    func,
    select,
    update,
)
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import Operator, Reader, audit
from app.liveops import (
    VN,
    BossRules,
    QuestMatchLog,
    Reward,
    apply_facts,
    aware,
    event_config,
    event_window,
    grant,
    quest_view,
    quests_for,
    reward_view,
    shop_view,
    token_wallet,
    vn_day,
)
from app.main import Account, Base, Db, Identity
from app.matches import arena_service

router = APIRouter()

RESULTS = ("WIN", "LOSE", "TIMEOUT", "ABORT")
# Reasons a raider gets no (full) reward; shown in the result dialog.
REASONS = {
    "ABORTED": "Trận bị hủy",
    "PRIVATE_ROOM": "Phòng riêng không nhận thưởng",
    "NOT_ACTIVE": "Chưa tham gia đủ thời gian",
    "AFK": "Không hoạt động (AFK)",
    "NO_CONTRIBUTION": "Chưa đóng góp đủ (sát thương hoặc hỗ trợ)",
    "DAILY_LIMIT": "Đã hết lượt thưởng hôm nay",
    "NO_ACCOUNT": "Tài khoản không tồn tại",
}


def now() -> datetime:
    return datetime.now(UTC)


def enabled() -> bool:
    """Kill switch: BOSS_EVENTS_ENABLED=0 stops new raids and hides boss events."""
    return os.environ.get("BOSS_EVENTS_ENABLED", "1") != "0"


# ---------------------------------------------------------------- tables


class BossRaidMatch(Base):
    __tablename__ = "boss_raid_matches"
    # The arena's id: "<process>.<room>.<round>" (unique, so retries record once).
    id: Mapped[str] = mapped_column(String(120), primary_key=True)
    event_id: Mapped[str] = mapped_column(String(36), index=True)
    room_id: Mapped[str] = mapped_column(String(64))
    boss_id: Mapped[str] = mapped_column(String(32))
    map_id: Mapped[str] = mapped_column(String(24), default="")
    result: Mapped[str] = mapped_column(String(8))
    hp_max: Mapped[int] = mapped_column(Integer)
    hp_left: Mapped[int] = mapped_column(Integer, default=0)
    duration_ms: Mapped[int] = mapped_column(Integer)
    private: Mapped[bool] = mapped_column(Boolean, default=False)
    players: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class BossRaidParticipant(Base):
    __tablename__ = "boss_raid_participants"
    match_id: Mapped[str] = mapped_column(String(120), primary_key=True)
    account_id: Mapped[str] = mapped_column(String(36), primary_key=True, index=True)
    name: Mapped[str] = mapped_column(String(24))
    damage: Mapped[int] = mapped_column(Integer, default=0)
    support: Mapped[int] = mapped_column(Integer, default=0)
    actions: Mapped[int] = mapped_column(Integer, default=0)
    active_ms: Mapped[int] = mapped_column(Integer, default=0)
    alive: Mapped[bool] = mapped_column(Boolean, default=False)
    # full = win reward, consolation = lose/timeout reward, none = see reason.
    reward: Mapped[str] = mapped_column(String(12), default="none")
    reason: Mapped[str] = mapped_column(String(16), default="")


class BossRewardGrant(Base):
    __tablename__ = "boss_reward_grants"
    __table_args__ = (UniqueConstraint("match_id", "account_id", "kind"),)
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    match_id: Mapped[str] = mapped_column(String(120))
    account_id: Mapped[str] = mapped_column(String(36), index=True)
    event_id: Mapped[str] = mapped_column(String(36), index=True)
    kind: Mapped[str] = mapped_column(String(12))  # full | consolation
    # ELIGIBLE -> CLAIMED, or EXPIRED after the event's claim window (settle).
    status: Mapped[str] = mapped_column(String(10), default="ELIGIBLE")
    rewards: Mapped[list] = mapped_column(JSON)
    day: Mapped[str] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


# ---------------------------------------------------------------- schedule


def boss_rules(event) -> BossRules | None:
    return event_config(event).boss if event is not None else None


def in_session(rules: BossRules, at: datetime) -> bool:
    if not rules.sessions:
        return True
    local = at.astimezone(VN)
    clock = local.strftime("%H:%M")
    return any(
        local.isoweekday() in s.days_of_week and s.local_start <= clock < s.local_end
        for s in rules.sessions
    )


def next_session(rules: BossRules, at: datetime) -> datetime | None:
    """Start of the next session within a week (None = always open)."""
    if not rules.sessions:
        return None
    local = at.astimezone(VN)
    for offset in range(8):
        day = (local + timedelta(days=offset)).date()
        for s in sorted(rules.sessions, key=lambda s: s.local_start):
            if day.isoweekday() not in s.days_of_week:
                continue
            hour, minute = map(int, s.local_start.split(":"))
            start = datetime(day.year, day.month, day.day, hour, minute, tzinfo=VN)
            if start > local:
                return start.astimezone(UTC)
    return None


def open_now(event, at: datetime) -> bool:
    from app.admin_api import event_phase

    rules = boss_rules(event)
    return (
        enabled()
        and rules is not None
        and event_phase(event) == "running"
        and in_session(rules, at)
    )


def boss_events(db: Session) -> list:
    from app.admin_api import GameEvent

    rows = db.scalars(select(GameEvent).where(GameEvent.status.in_(("published", "paused"))))
    return [e for e in rows if boss_rules(e) is not None]


# ---------------------------------------------------------------- arena


def arena_rules(event) -> dict:
    rules = boss_rules(event)
    data = rules.model_dump(
        include={
            "boss_id",
            "asset_pack_id",
            "display_name",
            "map_id",
            "base_hp",
            "hp_per_extra_player",
            "phase_thresholds",
            "skills",
            "bomb_damage",
            "weak_multiplier",
            "min_players",
            "max_players",
            "duration_seconds",
            "items",
            "mount",
            "footprint",
            "walk_ms",
            "rescue_ms",
            "hp_formula",
        }
    )
    return data


@router.get("/internal/v1/boss/events/{event_id}", dependencies=[Depends(arena_service)])
def arena_boss_event(event_id: str, db: Db):
    from app.admin_api import GameEvent

    event = db.get(GameEvent, event_id)
    if event is None or boss_rules(event) is None or event.status == "draft":
        raise HTTPException(404, "Boss event not found")
    return {"open": open_now(event, now()), "rules": arena_rules(event)}


def used_today(db: Session, account_id: str, event_id: str, kind: str, day: str) -> int:
    return db.scalar(
        select(func.count())
        .select_from(BossRewardGrant)
        .where(
            BossRewardGrant.account_id == account_id,
            BossRewardGrant.event_id == event_id,
            BossRewardGrant.kind == kind,
            BossRewardGrant.day == day,
        )
    )


def judge(
    rules: BossRules, result: str, private: bool, hp_max: int, duration_ms: int, raider
) -> tuple[str, str]:
    """(reward kind, reason) before the daily limit: full / consolation / none."""
    rule = rules.eligibility
    if result == "ABORT":
        return "none", "ABORTED"
    if private and not rules.reward_private_room:
        return "none", "PRIVATE_ROOM"
    need_ms = 1000 * min(rule.min_active_seconds, rule.min_active_fraction * duration_ms / 1000)
    if raider.active_ms < need_ms:
        return "none", "NOT_ACTIVE"
    if raider.actions < rule.min_actions:
        return "none", "AFK"
    if result != "WIN":
        return "consolation", ""
    if raider.damage < rule.min_damage_fraction * hp_max and raider.support < rule.support_actions:
        return "none", "NO_CONTRIBUTION"
    return "full", ""


def record_raid(db: Session, event_in) -> BossRaidMatch | None:
    """Stores one raid once (QA-13/14: retries and duplicate workers record it once)."""
    from app.admin_api import GameEvent

    if event_in.result not in RESULTS or not event_in.match_id or not event_in.event_id:
        raise HTTPException(422, "Incomplete boss raid")
    if db.get(BossRaidMatch, event_in.match_id) is not None:
        return None
    event = db.get(GameEvent, event_in.event_id)
    rules = boss_rules(event)
    if rules is None:
        raise HTTPException(422, "Unknown boss event")
    at = now()
    day = vn_day(at).isoformat()
    match = BossRaidMatch(
        id=event_in.match_id,
        event_id=event.id,
        room_id=event_in.room_id,
        boss_id=event_in.boss_id or rules.boss_id,
        map_id=event_in.map_id or rules.map_id,
        result=event_in.result,
        hp_max=event_in.boss_hp_max,
        hp_left=event_in.boss_hp_left,
        duration_ms=event_in.duration_ms,
        private=event_in.private,
        players=len(event_in.raiders),
        created_at=at,
    )
    try:
        with db.begin_nested():
            db.add(match)
            db.flush()
    except IntegrityError:
        return None  # a concurrent worker recorded it first
    for raider in event_in.raiders:
        kind, reason = judge(
            rules, match.result, match.private, match.hp_max, match.duration_ms, raider
        )
        account = db.get(Account, raider.account_id)
        if account is None:
            kind, reason = "none", "NO_ACCOUNT"
        if kind != "none" and used_today(db, raider.account_id, event.id, kind, day) >= (
            rules.full_reward_limit_per_day
        ):
            kind, reason = "none", "DAILY_LIMIT"
        rewards = rules.win_rewards if kind == "full" else rules.lose_rewards
        if kind == "consolation" and not rewards:
            kind = "none"
        db.add(
            BossRaidParticipant(
                match_id=match.id,
                account_id=raider.account_id,
                name=raider.name[:24],
                damage=raider.damage,
                support=raider.support,
                actions=raider.actions,
                active_ms=raider.active_ms,
                alive=raider.alive,
                reward=kind,
                reason=reason,
            )
        )
        if kind != "none":
            db.add(
                BossRewardGrant(
                    id=str(uuid.uuid4()),
                    match_id=match.id,
                    account_id=raider.account_id,
                    event_id=event.id,
                    kind=kind,
                    status="ELIGIBLE",
                    rewards=[r.model_dump() for r in rewards],
                    day=day,
                    created_at=at,
                )
            )
        # Quest progress: valid participation only, once per (account, raid).
        if account is not None and reason in ("", "DAILY_LIMIT", "NO_CONTRIBUTION"):
            if db.get(QuestMatchLog, (account.id, match.id[:36])) is None:
                db.add(
                    QuestMatchLog(
                        account_id=account.id,
                        match_id=match.id[:36],
                        source="boss",
                        day=day,
                        created_at=at,
                    )
                )
                apply_facts(
                    db,
                    account.id,
                    {
                        "match": True,
                        "mode": "boss",
                        "map_id": match.map_id,
                        "won": match.result == "WIN",
                        "damage": raider.damage,
                        "support": raider.support,
                    },
                    at,
                )
    from app.progression import settle_boss

    settle_boss(db, match, event_in.raiders, rules, event_in.team_size)
    return match


# ---------------------------------------------------------------- player API


def rules_view(rules: BossRules, token_name: str) -> dict:
    hp = [
        round(rules.base_hp * (0.6 + 0.1 * n))
        if rules.hp_formula == "team"
        else round(rules.base_hp * (1 + rules.hp_per_extra_player * (n - 1)))
        for n in (1, 8)
    ]
    return {
        "boss_id": rules.boss_id,
        "asset_pack_id": rules.asset_pack_id,
        "display_name": rules.display_name,
        "map_id": rules.map_id,
        "difficulty": rules.difficulty,
        "rescue_ms": rules.rescue_ms,
        "footprint": rules.footprint,
        "walk_ms": rules.walk_ms,
        "min_players": rules.min_players,
        "max_players": rules.max_players,
        "duration_seconds": rules.duration_seconds,
        "hp_solo": hp[0],
        "hp_full": hp[1],
        "phase_thresholds": rules.phase_thresholds,
        "skills": rules.skills,
        "items": rules.items,
        "mount": rules.mount,
        "reward_private_room": rules.reward_private_room,
        "full_reward_limit_per_day": rules.full_reward_limit_per_day,
        "win_rewards": [reward_view(r, token_name) for r in rules.win_rewards],
        "lose_rewards": [reward_view(r, token_name) for r in rules.lose_rewards],
        "sessions": [s.model_dump() for s in rules.sessions],
    }


def my_progress(db: Session, account_id: str, event) -> dict:
    day = vn_day(now()).isoformat()
    wins = db.scalar(
        select(func.count())
        .select_from(BossRaidParticipant)
        .join(BossRaidMatch, BossRaidMatch.id == BossRaidParticipant.match_id)
        .where(
            BossRaidParticipant.account_id == account_id,
            BossRaidMatch.event_id == event.id,
            BossRaidMatch.result == "WIN",
        )
    )
    pending = db.scalar(
        select(func.count())
        .select_from(BossRewardGrant)
        .where(
            BossRewardGrant.account_id == account_id,
            BossRewardGrant.event_id == event.id,
            BossRewardGrant.status == "ELIGIBLE",
        )
    )
    return {
        "wins": int(wins or 0),
        "full_rewards_today": used_today(db, account_id, event.id, "full", day),
        "pending_rewards": int(pending or 0),
        "badges": token_wallet(db, account_id, event.id).balance,
    }


def boss_event_view(db: Session, account_id: str, event, at: datetime) -> dict:
    from app.admin_api import event_phase

    config = event_config(event)
    rules = config.boss
    window = event_window(event, at)
    quests = [
        quest_view(db, account_id, q, at, window)
        for q in quests_for(db, at, [event])
        if q.event is event
    ]
    return {
        "id": event.id,
        "name": event.name,
        "description": event.description,
        "banner": config.banner,
        "intro": config.intro,
        "badge_name": config.token_name,
        "phase": event_phase(event),
        "window": window,
        "start_at": aware(event.start_at),
        "end_at": aware(event.end_at),
        "claim_end_at": aware(event.claim_end_at) or aware(event.end_at),
        "open": open_now(event, at),
        "in_session": in_session(rules, at),
        "next_session": next_session(rules, at),
        "timezone": "Asia/Ho_Chi_Minh",
        "server_time": at,
        "rules": rules_view(rules, config.token_name),
        "me": my_progress(db, account_id, event),
        "quests": quests,
        "shop": shop_view(db, account_id, event, config),
    }


@router.get("/v1/boss/events")
def player_boss_events(account: Identity, db: Db):
    """Boss events a player can see: running, scheduled (QA-01) or in claim window."""
    if not enabled():
        return {"events": [], "enabled": False}
    at = now()
    # Running or in the claim window, scheduled (shown with its start), or paused.
    shown = [
        e
        for e in boss_events(db)
        if e.status == "paused" or event_window(e, at) != "closed" or aware(e.start_at) > at
    ]
    # Running events first, newest first: older apps only show the first one.
    shown.sort(key=lambda e: (event_window(e, at) != "progress", -aware(e.start_at).timestamp()))
    return {
        "enabled": True,
        "events": [boss_event_view(db, account.id, e, at) for e in shown],
    }


def grant_view(row: BossRewardGrant, token_name: str) -> dict:
    return {
        "id": row.id,
        "match_id": row.match_id,
        "event_id": row.event_id,
        "kind": row.kind,
        "status": row.status,
        "rewards": [reward_view(Reward(**r), token_name) for r in row.rewards],
        "created_at": row.created_at,
        "claimed_at": row.claimed_at,
    }


def token_name_of(db: Session, event_id: str) -> str:
    from app.admin_api import GameEvent

    event = db.get(GameEvent, event_id)
    return event_config(event).token_name if event else "Huy Hiệu"


@router.get("/v1/boss/raids/{match_id}/result")
def raid_result(match_id: str, account: Identity, db: Db):
    """The server's result for one raid and this player's reward (or the reason)."""
    match = db.get(BossRaidMatch, match_id)
    me = db.get(BossRaidParticipant, (match_id, account.id))
    if match is None or me is None:
        raise HTTPException(404, "Raid result not found")
    grants = db.scalars(
        select(BossRewardGrant).where(
            BossRewardGrant.match_id == match_id, BossRewardGrant.account_id == account.id
        )
    )
    name = token_name_of(db, match.event_id)
    return {
        "match_id": match.id,
        "event_id": match.event_id,
        "result": match.result,
        "hp_max": match.hp_max,
        "hp_left": match.hp_left,
        "duration_ms": match.duration_ms,
        "private": match.private,
        "me": {
            "damage": me.damage,
            "support": me.support,
            "active_ms": me.active_ms,
            "alive": me.alive,
            "reward": me.reward,
            "reason": me.reason,
            "reason_text": REASONS.get(me.reason, ""),
        },
        "grants": [grant_view(g, name) for g in grants],
    }


@router.get("/v1/boss/rewards")
def my_rewards(account: Identity, db: Db):
    rows = db.scalars(
        select(BossRewardGrant)
        .where(BossRewardGrant.account_id == account.id, BossRewardGrant.status == "ELIGIBLE")
        .order_by(BossRewardGrant.created_at.desc())
        .limit(50)
    )
    names: dict[str, str] = {}
    out = []
    for row in rows:
        if row.event_id not in names:
            names[row.event_id] = token_name_of(db, row.event_id)
        out.append(grant_view(row, names[row.event_id]))
    return {"rewards": out}


class ClaimBody(BaseModel):
    request_id: str = Field(default="", max_length=64)


@router.post("/v1/boss/rewards/{grant_id}/claim")
def claim_reward(grant_id: str, body: ClaimBody, account: Identity, db: Db):
    """Idempotent (QA-12): two devices or retries grant once; the second sees CLAIMED."""
    from app.admin_api import GameEvent

    row = db.get(BossRewardGrant, grant_id)
    if row is None or row.account_id != account.id:
        raise HTTPException(404, "Reward not found")
    name = token_name_of(db, row.event_id)
    if row.status == "CLAIMED":
        return {**grant_view(row, name), "already": True}
    if row.status != "ELIGIBLE":
        raise HTTPException(409, "Reward expired")
    event = db.get(GameEvent, row.event_id)
    if event is not None and event_window(event, now()) == "closed":
        raise HTTPException(409, "Claim window closed")
    # Conditional update: only one transaction turns ELIGIBLE into CLAIMED.
    claimed = db.execute(
        update(BossRewardGrant)
        .where(BossRewardGrant.id == grant_id, BossRewardGrant.status == "ELIGIBLE")
        .values(status="CLAIMED", claimed_at=now())
    )
    if claimed.rowcount != 1:
        db.rollback()
        db.refresh(row)
        return {**grant_view(row, name), "already": True}
    grant(db, account, [Reward(**r) for r in row.rewards], row.event_id, f"boss:{row.id}")
    db.commit()
    db.refresh(row)
    from app.economy import wallet_view

    return {**grant_view(row, name), "already": False, "wallet": wallet_view(db, account)}


# ---------------------------------------------------------------- admin API


def percentile(values: list[int], share: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(share * len(ordered)))]


@router.get("/admin/v1/boss/events/{event_id}/analytics")
def admin_boss_analytics(event_id: str, _: Reader, db: Db):
    """LiveOps board (spec section 11): starts, results, TTK, payout, rejections."""
    from app.admin_api import get_event

    event = get_event(db, event_id)
    matches = list(db.scalars(select(BossRaidMatch).where(BossRaidMatch.event_id == event.id)))
    ids = [m.id for m in matches]
    people = (
        list(db.scalars(select(BossRaidParticipant).where(BossRaidParticipant.match_id.in_(ids))))
        if ids
        else []
    )
    grants = list(db.scalars(select(BossRewardGrant).where(BossRewardGrant.event_id == event.id)))
    wins = [m for m in matches if m.result == "WIN"]
    by_result = {r: sum(1 for m in matches if m.result == r) for r in RESULTS}
    finished = by_result["WIN"] + by_result["LOSE"] + by_result["TIMEOUT"]
    payout: dict[str, int] = {}
    for g in grants:
        if g.status != "CLAIMED":
            continue
        for r in g.rewards:
            key = r["type"] if r["type"] != "item" else f"item:{r.get('item_id')}"
            payout[key] = payout.get(key, 0) + int(r.get("amount", 1))
    reasons: dict[str, int] = {}
    for p in people:
        if p.reason:
            reasons[p.reason] = reasons.get(p.reason, 0) + 1
    return {
        "raids": len(matches),
        "by_result": by_result,
        "win_rate": round(by_result["WIN"] / finished, 3) if finished else 0,
        "ttk_median_s": percentile([m.duration_ms for m in wins], 0.5) // 1000,
        "ttk_p95_s": percentile([m.duration_ms for m in wins], 0.95) // 1000,
        "participants": len({p.account_id for p in people}),
        "avg_team": round(sum(m.players for m in matches) / len(matches), 2) if matches else 0,
        "private_raids": sum(1 for m in matches if m.private),
        "grants": {
            s: sum(1 for g in grants if g.status == s) for s in ("ELIGIBLE", "CLAIMED", "EXPIRED")
        },
        "payout_claimed": payout,
        "rejected": reasons,
        "afk": reasons.get("AFK", 0),
    }


@router.get("/admin/v1/boss/events/{event_id}/raids")
def admin_boss_raids(event_id: str, _: Reader, db: Db, limit: int = 50):
    from app.admin_api import get_event

    event = get_event(db, event_id)
    rows = list(
        db.scalars(
            select(BossRaidMatch)
            .where(BossRaidMatch.event_id == event.id)
            .order_by(BossRaidMatch.created_at.desc())
            .limit(min(200, max(1, limit)))
        )
    )
    out = []
    for m in rows:
        people = db.scalars(select(BossRaidParticipant).where(BossRaidParticipant.match_id == m.id))
        out.append(
            {
                "match_id": m.id,
                "result": m.result,
                "hp_max": m.hp_max,
                "hp_left": m.hp_left,
                "duration_ms": m.duration_ms,
                "private": m.private,
                "created_at": m.created_at,
                "players": [
                    {
                        "account_id": p.account_id,
                        "name": p.name,
                        "damage": p.damage,
                        "support": p.support,
                        "active_ms": p.active_ms,
                        "reward": p.reward,
                        "reason": p.reason,
                    }
                    for p in people
                ],
            }
        )
    return {"raids": out}


@router.post("/admin/v1/boss/events/{event_id}/settle")
def admin_boss_settle(event_id: str, admin: Operator, db: Db):
    """After the claim window: unclaimed rewards become EXPIRED (audited, repeatable)."""
    from app.admin_api import get_event

    event = get_event(db, event_id)
    if boss_rules(event) is None:
        raise HTTPException(409, "Not a boss event")
    if event_window(event, now()) != "closed" or aware(event.start_at) > now():
        raise HTTPException(409, "Settle after the claim window has closed")
    expired = db.execute(
        update(BossRewardGrant)
        .where(BossRewardGrant.event_id == event.id, BossRewardGrant.status == "ELIGIBLE")
        .values(status="EXPIRED")
    ).rowcount
    audit(db, admin, "boss.settle", "event", event.id, expired=expired)
    db.commit()
    return {"expired": expired}
