from datetime import UTC, datetime, timedelta

from app import admin_api, boss, liveops
from tests.test_liveops import ARENA, INGEST, arena_round, db_session, quests, seed
from tests.test_sync import item, overrides, owner, player, service_token  # noqa: F401

ARENA_SERVICE = {"Authorization": "Bearer " + service_token()}
ITEMS = (
    ("effect_star", "effect"),
    ("wings_golden_light", "wings"),
    ("pet_dragon", "pet"),
    ("effect_fire", "effect"),
    ("blue_shield", "consumable"),
)


def reward_items(client, admin):
    """Items the boss template rewards / sells (once per test database)."""
    with db_session() as db:
        missing = [(i, c) for i, c in ITEMS if db.get(admin_api.ItemCatalog, i) is None]
    for item_id, category in missing:
        item(client, admin, item_id, category=category)


def boss_event(client, admin, sessions=None, publish=True, **rules):
    """The spec's sample event, running now (sessions empty = always open)."""
    reward_items(client, admin)
    template = client.get("/admin/v1/events/template?kind=boss", headers=admin).json()
    started = datetime.now(UTC) - timedelta(hours=1)
    template["start_at"] = started.isoformat()
    template["end_at"] = (started + timedelta(days=7)).isoformat()
    template["claim_end_at"] = (started + timedelta(days=10)).isoformat()
    template["config"]["boss"] = {"sessions": sessions or [], **rules}
    created = client.post("/admin/v1/events", json=template, headers=admin)
    assert created.status_code == 201, created.json()
    event = created.json()
    if publish:
        client.post(f"/admin/v1/events/{event['id']}/publish", headers=admin)
    return event["id"]


def raider(account, **extra):
    return {
        "account_id": account,
        "name": account[:8],
        "damage": 300,
        "support": 0,
        "actions": 50,
        "active_ms": 120_000,
        "alive": True,
        **extra,
    }


def raid(client, event_id, match, result, raiders, private=False, hp=1000):
    body = {
        "type": "boss_raid",
        "room_id": "bossroom",
        "process_id": "p1",
        "event_id": event_id,
        "match_id": match,
        "result": result,
        "boss_id": "boss_001",
        "boss_hp_max": hp,
        "boss_hp_left": 0 if result == "WIN" else hp // 2,
        "duration_ms": 120_000,
        "map_id": "harbor",
        "private": private,
        "raiders": raiders,
    }
    response = client.post(ARENA, json=body, headers=INGEST)
    assert response.status_code == 204, response.text


def result(client, headers, match):
    return client.get(f"/v1/boss/raids/{match}/result", headers=headers).json()


def test_admin_validation_blocks_bad_boss_config(client):
    admin = owner(client)
    reward_items(client, admin)
    template = client.get("/admin/v1/events/template?kind=boss", headers=admin).json()
    assert template["kind"] == "boss" and template["config"]["token_name"] == "Huy Hiệu Boss"
    check = client.post("/admin/v1/events/validate", json=template, headers=admin).json()
    assert check["ok"], check
    # Daily boss badges for 7 days x 3 wins, plus the badge quests.
    assert check["max_tokens"] >= 30 * 3 * 7

    def broken(**boss_rules):
        config = {**template["config"], "boss": {**template["config"]["boss"], **boss_rules}}
        return client.post(
            "/admin/v1/events/validate", json={**template, "config": config}, headers=admin
        )

    bad = broken(map_id="mars", phase_thresholds=[0.35, 0.7]).json()
    assert not bad["ok"]
    assert any("mars" in e for e in bad["errors"]) and any("phase" in e for e in bad["errors"])
    assert not broken(skills=["boss_block_lane"]).json()["ok"]  # nothing that hurts
    assert not broken(win_rewards=[{"type": "item", "item_id": "nope"}]).json()["ok"]
    assert not broken(min_players=6, max_players=4).json()["ok"]
    assert broken(max_players=9).status_code == 422  # schema: at most 8
    assert broken(skills=["boss_teleport"]).status_code == 422
    # Boss objectives need a boss block.
    story = client.get("/admin/v1/events/template", headers=admin).json()
    story["config"]["quests"].append(template["config"]["quests"][0])
    errors = client.post("/admin/v1/events/validate", json=story, headers=admin).json()
    assert any("Boss" in e for e in errors["errors"])


def test_robot_template_validates_and_reaches_the_arena(client):
    admin = owner(client)
    reward_items(client, admin)
    template = client.get("/admin/v1/events/template?kind=robot", headers=admin).json()
    rules = template["config"]["boss"]
    assert template["kind"] == "boss" and rules["display_name"] == "Robot Bom Dây Cót"
    assert rules["skills"] == list(liveops.ROBOT_SKILLS) and len(rules["skills"]) == 7
    assert (rules["footprint"], rules["walk_ms"], rules["base_hp"]) == (2, 700, 6000)
    assert (rules["min_players"], rules["max_players"], rules["duration_seconds"]) == (1, 6, 360)
    check = client.post("/admin/v1/events/validate", json=template, headers=admin).json()
    assert check["ok"], check

    def broken(**boss_rules):
        config = {**template["config"], "boss": {**rules, **boss_rules}}
        return client.post(
            "/admin/v1/events/validate", json={**template, "config": config}, headers=admin
        )

    assert broken(skills=["robot_reactor"]).json()["ok"]  # every robot skill hits
    assert not broken(walk_ms=100).json()["ok"]
    assert broken(footprint=4).status_code == 422
    # The arena gets the footprint and the walking speed.
    event_id = boss_event(client, admin, **{k: v for k, v in rules.items() if k != "sessions"})
    info = client.get(f"/internal/v1/boss/events/{event_id}", headers=ARENA_SERVICE).json()
    assert info["rules"]["footprint"] == 2 and info["rules"]["walk_ms"] == 700
    assert info["rules"]["skills"][0] == "robot_bomb_launch"


def test_cactus_and_ram_templates_validate_and_reach_the_arena(client):
    admin = owner(client)
    reward_items(client, admin)
    for kind, name, skills in (
        ("cactus", "Vua Xương Rồng", liveops.CACTUS_SKILLS),
        ("ram", "Cừu Sấm Sét", liveops.RAM_SKILLS),
    ):
        template = client.get(f"/admin/v1/events/template?kind={kind}", headers=admin).json()
        rules = template["config"]["boss"]
        assert template["kind"] == "boss" and rules["display_name"] == name
        assert rules["skills"] == list(skills)
        assert (rules["footprint"], rules["rescue_ms"], rules["hp_formula"]) == (2, 4000, "team")
        assert (rules["base_hp"], rules["bomb_damage"], rules["phase_thresholds"]) == (
            8000,
            100,
            [0.7, 0.3],
        )
        check = client.post("/admin/v1/events/validate", json=template, headers=admin).json()
        assert check["ok"] and not check["warnings"], check

        def broken(template=template, rules=rules, **boss_rules):
            config = {**template["config"], "boss": {**rules, **boss_rules}}
            return client.post(
                "/admin/v1/events/validate", json={**template, "config": config}, headers=admin
            ).json()

        assert not broken(footprint=3)["ok"]  # these bosses take 2 x 2
        mixed = broken(skills=[*skills, "boss_basic_hit"])
        assert mixed["ok"] and any("nhiều boss" in w for w in mixed["warnings"])
        assert any("1,5" in w for w in broken(rescue_ms=800)["warnings"])
        event_id = boss_event(client, admin, **{k: v for k, v in rules.items() if k != "sessions"})
        info = client.get(f"/internal/v1/boss/events/{event_id}", headers=ARENA_SERVICE).json()
        assert info["rules"]["rescue_ms"] == 4000 and info["rules"]["hp_formula"] == "team"
        _, headers = player(client, f"twin_{kind}")
        shown = [
            e
            for e in client.get("/v1/boss/events", headers=headers).json()["events"]
            if e["id"] == event_id
        ][0]
        assert (shown["rules"]["hp_solo"], shown["rules"]["hp_full"]) == (5600, 11200)
        assert shown["rules"]["rescue_ms"] == 4000


def test_players_see_the_newest_running_boss_event_first(client):
    admin = owner(client)
    older = boss_event(client, admin)
    newer = boss_event(client, admin, display_name="Robot Bom Dây Cót")
    _, headers = player(client, "boss_pick")
    ids = [e["id"] for e in client.get("/v1/boss/events", headers=headers).json()["events"]]
    assert {older, newer} <= set(ids)
    assert ids.index(newer) < ids.index(older)


def test_arena_reads_rules_and_open_state_from_the_schedule(client, monkeypatch):
    admin = owner(client)
    draft = boss_event(client, admin, publish=False, base_hp=1200, max_players=6)
    url = f"/internal/v1/boss/events/{draft}"
    assert client.get(url).status_code == 401  # service token only
    assert client.get(url, headers=ARENA_SERVICE).status_code == 404  # draft
    client.post(f"/admin/v1/events/{draft}/publish", headers=admin)
    info = client.get(url, headers=ARENA_SERVICE).json()
    assert info["open"] is True
    assert info["rules"]["base_hp"] == 1200 and info["rules"]["max_players"] == 6
    assert info["rules"]["map_id"] == "harbor" and "win_rewards" not in info["rules"]
    # Pause: no new raid (QA-17); resume opens again.
    client.post(f"/admin/v1/events/{draft}/pause", headers=admin)
    assert client.get(url, headers=ARENA_SERVICE).json()["open"] is False
    client.post(f"/admin/v1/events/{draft}/resume", headers=admin)
    assert client.get(url, headers=ARENA_SERVICE).json()["open"] is True
    # Kill switch.
    monkeypatch.setenv("BOSS_EVENTS_ENABLED", "0")
    assert client.get(url, headers=ARENA_SERVICE).json()["open"] is False
    monkeypatch.delenv("BOSS_EVENTS_ENABLED")
    # Sessions only on another weekday (Vietnam time): closed today.
    tomorrow = datetime.now(boss.VN).isoweekday() % 7 + 1
    closed = boss_event(
        client,
        admin,
        sessions=[{"days_of_week": [tomorrow], "local_start": "00:00", "local_end": "24:00"}],
    )
    info = client.get(f"/internal/v1/boss/events/{closed}", headers=ARENA_SERVICE).json()
    assert info["open"] is False


def test_raid_rewards_follow_eligibility_and_are_recorded_once(client):
    admin = owner(client)
    event_id = boss_event(client, admin)
    ana, ana_h = player(client, "boss_ana")
    bo, bo_h = player(client, "boss_bo")
    cara, cara_h = player(client, "boss_cara")
    dan, dan_h = player(client, "boss_dan")
    raiders = [
        raider(ana),
        raider(bo, actions=2),  # AFK
        raider(cara, active_ms=10_000),  # joined for 10 s of a 120 s raid
        raider(dan, damage=0, support=1),  # no damage, too little support
    ]
    raid(client, event_id, "p1.room.1", "WIN", raiders)
    raid(client, event_id, "p1.room.1", "WIN", raiders)  # retry: recorded once
    mine = result(client, ana_h, "p1.room.1")
    assert mine["result"] == "WIN" and mine["me"]["reward"] == "full"
    assert [g["status"] for g in mine["grants"]] == ["ELIGIBLE"]
    assert {"type": "token", "amount": 30, "item_id": None, "label": "Huy Hiệu Boss"} in mine[
        "grants"
    ][0]["rewards"]
    assert result(client, bo_h, "p1.room.1")["me"]["reason"] == "AFK"
    assert result(client, cara_h, "p1.room.1")["me"]["reason"] == "NOT_ACTIVE"
    dan_view = result(client, dan_h, "p1.room.1")
    assert dan_view["me"]["reason"] == "NO_CONTRIBUTION" and dan_view["grants"] == []
    assert dan_view["me"]["reason_text"]
    # Support alone (3 verified actions) is enough without damage.
    raid(client, event_id, "p1.room.2", "WIN", [raider(dan, damage=0, support=3)])
    assert result(client, dan_h, "p1.room.2")["me"]["reward"] == "full"
    # Someone else's result is not visible.
    assert client.get("/v1/boss/raids/p1.room.2/result", headers=ana_h).status_code == 404


def test_claim_is_idempotent_and_pays_coins_and_badges(client):
    admin = owner(client)
    event_id = boss_event(client, admin)
    ana, ana_h = player(client, "claim_ana")
    raid(client, event_id, "p1.c.1", "WIN", [raider(ana)])
    pending = client.get("/v1/boss/rewards", headers=ana_h).json()["rewards"]
    assert len(pending) == 1
    gold = client.get("/v1/wallet", headers=ana_h).json()["gold"]
    url = f"/v1/boss/rewards/{pending[0]['id']}/claim"
    first = client.post(url, json={"request_id": "boss-claim-1"}, headers=ana_h).json()
    assert first["status"] == "CLAIMED" and first["already"] is False
    assert first["wallet"]["gold"] == gold + 150
    again = client.post(url, json={"request_id": "boss-claim-2"}, headers=ana_h).json()
    assert again["already"] is True
    assert client.get("/v1/wallet", headers=ana_h).json()["gold"] == gold + 150
    view = client.get("/v1/boss/events", headers=ana_h).json()["events"][0]
    assert view["me"]["badges"] == 30 and view["me"]["pending_rewards"] == 0
    assert view["me"]["wins"] == 1 and view["me"]["full_rewards_today"] == 1
    # Another player cannot claim it.
    _, bo_h = player(client, "claim_bo")
    assert client.post(url, json={}, headers=bo_h).status_code == 404


def test_daily_limit_consolation_private_and_abort(client):
    admin = owner(client)
    event_id = boss_event(client, admin)
    ana, ana_h = player(client, "limit_ana")
    for n in range(1, 5):
        raid(client, event_id, f"p1.l.{n}", "WIN", [raider(ana)])
    assert result(client, ana_h, "p1.l.3")["me"]["reward"] == "full"
    fourth = result(client, ana_h, "p1.l.4")["me"]
    assert fourth["reward"] == "none" and fourth["reason"] == "DAILY_LIMIT"
    # Lose / timeout: consolation (20 gold), never the win reward or a chest.
    raid(client, event_id, "p1.l.5", "TIMEOUT", [raider(ana)])
    lost = result(client, ana_h, "p1.l.5")
    assert lost["me"]["reward"] == "consolation"
    assert lost["grants"][0]["rewards"] == [{"type": "gold", "amount": 20, "item_id": None}]
    # Private rooms earn nothing by default; ABORT never rewards nor uses quota.
    bo, bo_h = player(client, "limit_bo")
    raid(client, event_id, "p1.l.6", "WIN", [raider(bo)], private=True)
    assert result(client, bo_h, "p1.l.6")["me"]["reason"] == "PRIVATE_ROOM"
    raid(client, event_id, "p1.l.7", "ABORT", [raider(bo)])
    assert result(client, bo_h, "p1.l.7")["me"]["reason"] == "ABORTED"
    raid(client, event_id, "p1.l.8", "WIN", [raider(bo)])
    assert result(client, bo_h, "p1.l.8")["me"]["reward"] == "full"


def test_boss_quests_progress_only_from_valid_raids(client):
    seed()
    admin = owner(client)
    event_id = boss_event(client, admin)
    ana, ana_h = player(client, "quest_ana")
    bo, _ = player(client, "quest_bo")
    raid(client, event_id, "p1.q.1", "WIN", [raider(ana)])
    raid(client, event_id, "p1.q.2", "WIN", [raider(ana, actions=1)])  # AFK: no progress
    view = client.get("/v1/boss/events", headers=ana_h).json()["events"][0]
    by_key = {q["key"].rsplit(".", 1)[1]: q for q in view["quests"]}
    assert by_key["BOSS_DAILY_PLAY_1"]["status"] == "completed"
    assert by_key["BOSS_DAILY_WIN_1"]["status"] == "completed"
    assert by_key["BOSS_WIN_3"]["objectives"][0]["progress"] == 1
    assert by_key["BOSS_WEEKLY_WIN_5"]["period"].count("-W") == 1
    claimed = client.post(
        f"/v1/quests/{by_key['BOSS_DAILY_WIN_1']['key']}/claim",
        json={"request_id": "boss-q-00001"},
        headers=ana_h,
    )
    assert claimed.status_code == 200 and claimed.json()["tokens"] == 10
    # A boss raid is not a PvP match for the daily D02 quest, and PvP does not move boss quests.
    daily = {q["key"]: q for q in quests(client, ana_h)["daily"]["quests"]}
    assert daily["D02"]["objectives"][0]["progress"] == 0
    arena_round(client, "pvp", 1, [ana, bo], "harbor", winner=ana)
    view = client.get("/v1/boss/events", headers=ana_h).json()["events"][0]
    by_key = {q["key"].rsplit(".", 1)[1]: q for q in view["quests"]}
    assert by_key["BOSS_WIN_3"]["objectives"][0]["progress"] == 1


def test_scheduled_events_show_their_time_and_analytics_settle(client):
    admin = owner(client)
    event_id = boss_event(client, admin)
    ana, ana_h = player(client, "ops_ana")
    raid(client, event_id, "p1.o.1", "WIN", [raider(ana)])
    raid(client, event_id, "p1.o.2", "LOSE", [raider(ana, actions=1)])
    stats = client.get(f"/admin/v1/boss/events/{event_id}/analytics", headers=admin).json()
    assert stats["raids"] == 2 and stats["by_result"]["WIN"] == 1
    assert stats["win_rate"] == 0.5 and stats["grants"]["ELIGIBLE"] == 1
    assert stats["rejected"] == {"AFK": 1} and stats["participants"] == 1
    raids = client.get(f"/admin/v1/boss/events/{event_id}/raids", headers=admin).json()
    assert raids["raids"][0]["players"][0]["account_id"] == ana
    settle = f"/admin/v1/boss/events/{event_id}/settle"
    assert client.post(settle, headers=admin).status_code == 409  # claim window still open
    # The event ends and its claim window closes: unclaimed rewards expire.
    with db_session() as db:
        event = db.get(admin_api.GameEvent, event_id)
        event.end_at = datetime.now(UTC) - timedelta(days=4)
        event.claim_end_at = datetime.now(UTC) - timedelta(days=1)
        event.start_at = datetime.now(UTC) - timedelta(days=8)
        db.commit()
    assert client.post(settle, headers=admin).json() == {"expired": 1}
    grant = client.get("/v1/boss/rewards", headers=ana_h).json()["rewards"]
    assert grant == []
    # A scheduled event is listed with its start, but not open (QA-01).
    later = boss_event(client, admin)
    with db_session() as db:
        event = db.get(admin_api.GameEvent, later)
        event.start_at = datetime.now(UTC) + timedelta(days=1)
        event.end_at = datetime.now(UTC) + timedelta(days=3)
        event.claim_end_at = None
        db.commit()
    shown = client.get("/v1/boss/events", headers=ana_h).json()["events"]
    upcoming = next(e for e in shown if e["id"] == later)
    assert upcoming["phase"] == "scheduled" and upcoming["open"] is False
    assert upcoming["timezone"] == "Asia/Ho_Chi_Minh"
    info = client.get(f"/internal/v1/boss/events/{later}", headers=ARENA_SERVICE).json()
    assert info["open"] is False
