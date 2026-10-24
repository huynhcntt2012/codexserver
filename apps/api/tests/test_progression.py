from datetime import UTC, datetime, timedelta

from app import progression
from tests.test_boss import boss_event, raider
from tests.test_liveops import ARENA, INGEST, db_session
from tests.test_sync import overrides, owner, player  # noqa: F401


def fighter(account, placement, **extra):
    """A player who really played: moved and bombed for the whole round."""
    return {
        "account_id": account,
        "name": account[:8],
        "placement": placement,
        "bombs": 4,
        "survived_ms": 60_000,
        "active_ms": 60_000,
        "groups": 2,
        **extra,
    }


def pvp(client, match, results, practice=False, duration=60_000):
    body = {
        "type": "match",
        "room_id": match.split(".")[1],
        "process_id": match.split(".")[0],
        "match_id": match,
        "map_name": "PARK",
        "map_id": "park",
        "round": int(match.split(".")[2]),
        "duration_ms": duration,
        "practice": practice,
        "results": results,
    }
    assert client.post(ARENA, json=body, headers=INGEST).status_code == 204


def exp(client, headers, match):
    return client.get(f"/v1/matches/{match}/exp", headers=headers)


def test_level_curve_matches_the_spec_table():
    assert [progression.required_xp(n) for n in (1, 2, 3, 5, 10, 12)] == [
        100,
        150,
        220,
        420,
        1270,
        1750,
    ]


def test_pvp_samples_349_and_123_once_per_match(client):
    ana, ana_h = player(client, "xp_ana")
    bo, bo_h = player(client, "xp_bo")
    results = [
        fighter(ana, 1, winner=True, kills=3, assists=2, hits=3, rescues=1),
        fighter(bo, 2, kills=1, hits=1, survived_ms=50_000),
    ]
    for _ in range(10):  # retried ingest: one award and one ledger row each
        pvp(client, "p1.room1.1", results)
    win = exp(client, ana_h, "p1.room1.1").json()
    assert win["eligible"] and win["result"] == "WIN" and win["awarded_exp"] == 349
    assert win["breakdown"] == {
        "completion": 50,
        "win": 100,
        "ko": 120,
        "assist": 40,
        "hit": 24,
        "rescue": 15,
    }
    assert (win["level_before"], win["level_after"], win["progress_after"]) == (1, 3, 99)
    lose = exp(client, bo_h, "p1.room1.1").json()
    assert lose["result"] == "LOSE" and lose["awarded_exp"] == 123
    me = client.get("/v1/progression/me", headers=ana_h).json()
    assert (me["level"], me["xp_in_level"], me["total_xp"]) == (3, 99, 349)
    assert me["next_level_required_exp"] == 220
    with db_session() as db:
        assert db.query(progression.MatchXpAward).count() == 2
        assert db.query(progression.XpLedger).count() == 2


def test_pvp_caps_draws_and_ineligible_players(client):
    ana, ana_h = player(client, "cap_ana")
    bo, bo_h = player(client, "cap_bo")
    cy, cy_h = player(client, "cap_cy")
    dee, dee_h = player(client, "cap_dee")
    pvp(
        client,
        "p1.room2.1",
        [
            # Every line maxed: 50 + 50 + 200 + 100 + 40 + 45 + 50 = 535, draw cap 300.
            fighter(ana, 1, kills=9, assists=9, hits=9, rescues=9, objectives=9),
            fighter(bo, 2, groups=1),  # only walked around: AFK
            fighter(cy, 3, active_ms=5_000, survived_ms=5_000),  # out at 5 s, barely played
            fighter(dee, 4, active_ms=12_000, survived_ms=12_000),  # out early, but played
        ],
    )
    draw = exp(client, ana_h, "p1.room2.1").json()
    assert draw["result"] == "DRAW" and draw["raw_exp"] == 535
    assert draw["capped"] and draw["awarded_exp"] == 300
    afk = exp(client, bo_h, "p1.room2.1").json()
    assert (afk["eligible"], afk["reason"], afk["awarded_exp"]) == (False, "AFK", 0)
    assert afk["reason_text"] and afk["support_code"]
    assert exp(client, cy_h, "p1.room2.1").json()["reason"] == "NOT_ACTIVE"
    early = exp(client, dee_h, "p1.room2.1").json()
    assert early["eligible"] and early["result"] == "LOSE" and early["awarded_exp"] == 75
    # Practice rooms with bots never give EXP.
    pvp(client, "p1.room3.1", [fighter(ana, 1, winner=True, kills=2)], practice=True)
    practice = exp(client, ana_h, "p1.room3.1").json()
    assert (practice["reason"], practice["awarded_exp"]) == ("PRACTICE", 0)
    assert exp(client, ana_h, "p1.nope.1").status_code == 404


def test_boss_samples_400_and_146_and_daily_factor(client):
    admin = owner(client)
    event_id = boss_event(client, admin)
    ana, ana_h = player(client, "boss_ana")
    bo, bo_h = player(client, "boss_bo")
    team = [
        raider(ana, damage=900, interrupts=2, rescues=1, support=1, phases=3),
        raider(bo, damage=200, interrupts=1, phases=2),
    ]

    def boss_raid(match, result, people, **extra):
        body_extra = {"team_size": 4, **extra}
        return raid_with(client, event_id, match, result, people, **body_extra)

    boss_raid("p1.b.1", "WIN", team)
    assert exp(client, ana_h, "p1.b.1").json()["awarded_exp"] == 400
    boss_raid("p1.b.2", "LOSE", team)
    lose = exp(client, bo_h, "p1.b.2").json()
    assert lose["breakdown"] == {
        "completion": 50,
        "lose": 25,
        "boss_damage": 36,
        "interrupt": 15,
        "phase": 20,
    }
    assert lose["awarded_exp"] == 146
    # Raids 3-7 of the day: the 6th and 7th valid ones get factor 0.5.
    for n in range(3, 8):
        boss_raid(f"p1.b.{n}", "LOSE", team)
    factors = [exp(client, bo_h, f"p1.b.{n}").json()["daily_factor"] for n in range(1, 8)]
    assert factors == [1.0, 1.0, 1.0, 1.0, 1.0, 0.5, 0.5]
    assert exp(client, bo_h, "p1.b.7").json()["awarded_exp"] == 73
    # An AFK raider gets nothing even when the boss falls; ABORT gives nothing.
    boss_raid("p1.b.8", "WIN", [raider(ana, damage=900, actions=2)])
    assert exp(client, ana_h, "p1.b.8").json()["reason"] == "AFK"
    boss_raid("p1.b.9", "ABORT", [raider(ana, damage=900)])
    assert exp(client, ana_h, "p1.b.9").json()["reason"] == "ABORTED"
    boss_raid("p1.b.10", "WIN", [raider(ana, damage=900)], private=True)
    assert exp(client, ana_h, "p1.b.10").json()["reason"] == "PRIVATE_ROOM"


def raid_with(client, event_id, match, result, people, private=False, team_size=0):
    """test_boss.raid with the EXP fields (HP 2650 as in the spec sample)."""
    body = {
        "type": "boss_raid",
        "room_id": "bossroom",
        "process_id": "p1",
        "event_id": event_id,
        "match_id": match,
        "result": result,
        "boss_id": "boss_001",
        "boss_hp_max": 2650,
        "boss_hp_left": 0 if result == "WIN" else 1000,
        "duration_ms": 120_000,
        "map_id": "harbor",
        "private": private,
        "team_size": team_size,
        "raiders": people,
    }
    response = client.post(ARENA, json=body, headers=INGEST)
    assert response.status_code == 204, response.text


def test_solo_and_full_team_damage_share():
    rules = progression.BossXpRules()
    assert progression.boss_damage_xp(rules, 2650, 2650, 1) == 120
    assert progression.boss_damage_xp(rules, 2650 // 8 + 1, 2650, 8) == 120
    assert progression.boss_damage_xp(rules, 99_999, 2650, 1) == 120  # overkill ignored
    assert progression.boss_damage_xp(rules, 0, 2650, 4) == 0


def test_published_rule_and_double_exp_apply_to_later_matches_only(client):
    admin = owner(client)
    ana, ana_h = player(client, "rule_ana")
    win = [fighter(ana, 1, winner=True, kills=3, assists=2, hits=3, rescues=1)]
    pvp(client, "p1.r.1", win)
    config = progression.XpConfig().model_dump(mode="json")
    config["pvp"]["completion"] = 60
    started = datetime.now(UTC) - timedelta(hours=1)
    config["multipliers"] = [
        {
            "name": "Double EXP",
            "start_at": started.isoformat(),
            "end_at": (started + timedelta(days=1)).isoformat(),
            "multiplier": 2.0,
        }
    ]
    bad = {**config, "multipliers": [{**config["multipliers"][0], "multiplier": 3}]}
    rejected = client.post("/admin/v1/exp/rules", json={"config": bad}, headers=admin)
    assert rejected.status_code == 422
    created = client.post("/admin/v1/exp/rules", json={"config": config}, headers=admin)
    assert created.status_code == 201 and created.json()["status"] == "draft"
    rule = created.json()["id"]
    pvp(client, "p1.r.2", win)  # drafts change nothing
    assert exp(client, ana_h, "p1.r.2").json()["awarded_exp"] == 349
    published = client.post(f"/admin/v1/exp/rules/{rule}/publish", headers=admin).json()
    assert published["status"] == "published"
    assert (
        client.put(
            f"/admin/v1/exp/rules/{rule}", json={"config": config}, headers=admin
        ).status_code
        == 409
    )
    with db_session() as db:  # published half an hour ago
        db.get(progression.XpRuleSet, rule).published_at = datetime.now(UTC) - timedelta(minutes=30)
        db.commit()
    # A round that started before the publish keeps the old rule.
    pvp(client, "p1.r.3", win, duration=3_600_000)
    assert exp(client, ana_h, "p1.r.3").json()["ruleset"]["version"] == 0
    pvp(client, "p1.r.4", win, duration=1_000)
    after = exp(client, ana_h, "p1.r.4").json()
    # Cap first (359 < 450), then x2.
    assert after["ruleset"]["version"] == 1 and after["event_multiplier"] == 2.0
    assert after["capped_base_exp"] == 359 and after["awarded_exp"] == 718
    assert exp(client, ana_h, "p1.r.1").json()["awarded_exp"] == 349
    rules = client.get("/admin/v1/exp/rules", headers=admin).json()
    assert rules["active"]["version"] == 1 and rules["preview"]["pvp_win"]["base"] == 359
    assert rules["level_curve"]["levels"][11] == {"level": 12, "required": 1750}


def test_multi_level_up_keeps_the_remainder_and_admin_tools(client):
    admin = owner(client)
    ana, ana_h = player(client, "lvl_ana")
    # 100 + 150 + 220 = 470 for level 4; 500 leaves 30 in level 4.
    body = {"amount": 500, "reason": "Bù EXP sự cố", "request_id": "adjust-0001"}
    path = f"/admin/v1/exp/players/{ana}/adjust"
    assert client.post(path, json=body, headers=admin).json()["progression"]["level"] == 4
    again = client.post(path, json=body, headers=admin).json()
    assert again["already"] and again["progression"]["total_xp"] == 500
    me = client.get("/v1/progression/me", headers=ana_h).json()
    assert (me["level"], me["xp_in_level"], me["next_level_required_exp"]) == (4, 30, 310)
    view = client.get(f"/admin/v1/exp/players/{ana}", headers=admin).json()
    assert view["ledger"][0]["source_type"] == "MANUAL_ADJUSTMENT"
    stats = client.get("/admin/v1/exp/stats", headers=admin)
    assert stats.status_code == 200
    # Players cannot reach the admin API.
    assert client.post(path, json=body, headers=ana_h).status_code == 401
    row = progression.PlayerProgression(level=1, xp_in_level=0, total_xp=0)
    progression.add_xp(row, 10_000_000)
    assert row.level == progression.LEVEL_CAP and row.xp_in_level == 0
    assert row.total_xp == 10_000_000
