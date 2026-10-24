from datetime import UTC, datetime, timedelta

from app import liveops, main
from tests.test_sync import item, overrides, owner, player, service_token  # noqa: F401

ARENA = "/internal/v1/arena/events"
INGEST = {"Authorization": "Bearer " + service_token()}


def db_session():
    return next(main.app.dependency_overrides[main.db_session]())


def seed():
    with db_session() as db:
        liveops.seed_defaults(db)


def arena_round(client, room, number, people, map_id="park", winner=None, bombs=3, practice=False):
    """One verified online round, the way the arena reports it."""
    body = {
        "type": "match",
        "room_id": room,
        "process_id": "p1",
        "map_name": map_id.upper(),
        "map_id": map_id,
        "round": number,
        "duration_ms": 60_000,
        "practice": practice,
        "results": [
            {
                "account_id": account,
                "name": f"p{i}",
                "placement": i + 1,
                "bombs": bombs,
                "winner": account == winner,
            }
            for i, account in enumerate(people)
        ],
    }
    assert client.post(ARENA, json=body, headers=INGEST).status_code == 204


def quests(client, headers):
    return client.get("/v1/quests", headers=headers).json()


def find(view, key):
    for scope in ("daily", "weekly"):
        for quest in view[scope]["quests"]:
            if quest["key"] == key:
                return quest
    raise KeyError(key)


def claim(client, headers, key, request="req-00000001"):
    return client.post(f"/v1/quests/{key}/claim", json={"request_id": request}, headers=headers)


def test_daily_weekly_progress_comes_from_verified_matches_once(client):
    seed()
    ana, ana_h = player(client, "ana_pilot")
    bo, bo_h = player(client, "bo_pilot")
    view = quests(client, ana_h)
    assert view["timezone"] == "Asia/Ho_Chi_Minh" and len(view["daily"]["quests"]) == 5
    # Opening the mission window is the day's check-in.
    assert find(view, "D01")["status"] == "completed" and view["claimable"] == 1
    gold = client.get("/v1/wallet", headers=ana_h).json()["gold"]
    first = claim(client, ana_h, "D01")
    assert first.status_code == 200 and first.json()["rewards"] == [
        {"type": "gold", "amount": 100, "item_id": None}
    ]
    assert first.json()["wallet"]["gold"] == gold + 100
    # Retry (or a second device) returns the same claim, never a second grant.
    again = claim(client, ana_h, "D01", "req-00000002")
    assert again.json()["claim_id"] == first.json()["claim_id"]
    assert client.get("/v1/wallet", headers=ana_h).json()["gold"] == gold + 100
    assert claim(client, ana_h, "D02").status_code == 409
    # Two verified rounds; the second report of round 2 is a retry and counts once.
    arena_round(client, "room1", 1, [ana, bo], "park", winner=ana)
    arena_round(client, "room1", 2, [ana, bo], "frost", winner=bo)
    arena_round(client, "room1", 2, [ana, bo], "frost", winner=bo)
    view = quests(client, ana_h)
    assert find(view, "D02")["status"] == "completed"
    assert find(view, "D03")["status"] == "completed"
    assert find(view, "D04")["status"] == "completed"
    assert find(view, "D05")["status"] == "in_progress"  # not friends yet
    assert find(view, "W01")["objectives"][0]["progress"] == 2
    assert find(view, "W02")["objectives"][0]["progress"] == 2
    # Friends: the next shared round completes "Hội bạn thân thiết" for both.
    request = client.post("/v1/friends/requests", json={"account_id": bo}, headers=ana_h).json()
    client.post(f"/v1/friends/requests/{request['request_id']}/accept", headers=bo_h)
    arena_round(client, "room1", 3, [ana, bo], "park")
    assert find(quests(client, ana_h), "D05")["status"] == "completed"
    assert find(quests(client, bo_h), "D05")["status"] == "completed"


def test_practice_counts_only_where_admin_allows_it(client):
    seed()
    admin = owner(client)
    ana, ana_h = player(client, "solo_pilot")
    practice_only = {
        "key": "D09",
        "scope": "daily",
        "title": "Luyện tập chăm chỉ",
        "objectives": [{"type": "MATCH_COMPLETED", "target": 1, "modes": ["practice"]}],
        "rewards": [{"type": "gold", "amount": 50}],
    }
    assert client.put("/admin/v1/quests/D09", json=practice_only, headers=admin).status_code == 200
    room = client.post(
        "/v1/practice/rooms", json={"map_name": "Park", "map_id": "park"}, headers=ana_h
    ).json()
    base = f"/v1/practice/rooms/{room['room_id']}/matches"
    me = {"name": "solo", "placement": 1, "winner": True, "bombs": 4}
    bot = {"name": "Bot", "is_bot": True, "placement": 2}
    short = {"round": 1, "duration_ms": 5_000, "participants": [me, bot]}
    assert client.post(base, json=short, headers=ana_h).status_code == 201
    assert find(quests(client, ana_h), "D09")["status"] == "in_progress"  # too short
    real = {"round": 2, "duration_ms": 45_000, "participants": [me, bot]}
    client.post(base, json=real, headers=ana_h)
    view = quests(client, ana_h)
    assert find(view, "D09")["status"] == "completed"
    assert find(view, "D02")["objectives"][0]["progress"] == 0  # online-only by default
    # A server practice room (friends + bots) is verified but still "practice".
    bo, _ = player(client, "bot_room_bo")
    arena_round(client, "prac", 1, [ana, bo], "park", winner=ana, practice=True)
    view = quests(client, ana_h)
    assert find(view, "D02")["objectives"][0]["progress"] == 0
    assert find(view, "D03")["status"] == "in_progress"
    bad = {
        **practice_only,
        "objectives": [{"type": "WITH_FRIEND", "target": 1, "modes": ["practice"]}],
    }
    assert client.put("/admin/v1/quests/D09", json=bad, headers=admin).status_code == 422
    unknown = {
        **practice_only,
        "objectives": [{"type": "MATCH_WON", "target": 1, "map_ids": ["mars"]}],
    }
    refused = client.put("/admin/v1/quests/D09", json=unknown, headers=admin)
    assert refused.status_code == 422 and "mars" in refused.json()["detail"]["errors"][0]


def test_story_event_chapters_tokens_and_shop(client):
    seed()
    admin = owner(client)
    for item_id, category in (
        ("effect_star", "effect"),
        ("pet_bunny", "pet"),
        ("outfit_mimi", "outfit"),
        ("flame_boost", "consumable"),
    ):
        item(client, admin, item_id, category=category)
    template = client.get("/admin/v1/events/template", headers=admin).json()
    assert template["config"]["chapters"][0]["map_id"] == "harbor"
    check = client.post("/admin/v1/events/validate", json=template, headers=admin).json()
    assert check["ok"] and check["max_tokens"] == 250 + 35 * 10
    broken = {
        **template,
        "config": {
            **template["config"],
            "chapters": [{**template["config"]["chapters"][0], "map_id": "mars"}],
        },
    }
    errors = client.post("/admin/v1/events/validate", json=broken, headers=admin).json()
    assert not errors["ok"] and any("mars" in e for e in errors["errors"])
    assert client.post("/admin/v1/events", json=broken, headers=admin).status_code == 422
    created = client.post("/admin/v1/events", json=template, headers=admin).json()
    url = f"/admin/v1/events/{created['id']}"
    ana, ana_h = player(client, "story_ana")
    bo, _ = player(client, "story_bo")
    assert quests(client, ana_h)["events"] == []  # draft is invisible
    assert client.post(url + "/publish", headers=admin).json()["version"] == 1
    event = quests(client, ana_h)["events"][0]
    assert event["token_name"] == "Vé Sao" and event["tokens"] == 0
    states = [c["state"] for c in event["chapters"]]
    assert states[0] == "playable" and states[1] == "locked"
    ch1 = event["chapters"][0]["quests"][0]
    # Rounds on another map do not count for chapter 1 (Bến Cảng only).
    arena_round(client, "r2", 1, [ana, bo], "park")
    arena_round(client, "r2", 2, [ana, bo], "harbor", winner=ana)
    arena_round(client, "r2", 3, [ana, bo], "harbor")
    event = quests(client, ana_h)["events"][0]
    assert event["chapters"][0]["quests"][0]["status"] == "completed"
    assert event["chapters"][0]["state"] == "cleared"
    daily = {q["key"].rsplit(".", 1)[1]: q for q in event["quests"]}
    assert daily["EVD1"]["status"] == "completed" and daily["EVD2"]["status"] == "completed"
    result = claim(client, ana_h, ch1["key"]).json()
    assert (
        result["tokens"] == 20
        and {"type": "token", "amount": 20, "item_id": None} in (result["rewards"])
    )
    claim(client, ana_h, daily["EVD1"]["key"], "req-00000003")
    claim(client, ana_h, daily["EVD2"]["key"], "req-00000004")
    assert quests(client, ana_h)["events"][0]["tokens"] == 55
    shop = f"/v1/events/{created['id']}/shop/orders"
    poor = client.post(shop, json={"sku": "star_fx", "request_id": "buy-00000001"}, headers=ana_h)
    assert poor.status_code == 409
    flame = client.post(shop, json={"sku": "flame", "request_id": "buy-00000002"}, headers=ana_h)
    assert flame.status_code == 201 and flame.json()["tokens"] == 25
    retry = client.post(shop, json={"sku": "flame", "request_id": "buy-00000002"}, headers=ana_h)
    assert retry.json()["order_id"] == flame.json()["order_id"] and retry.json()["tokens"] == 25
    entry = next(s for s in quests(client, ana_h)["events"][0]["shop"] if s["sku"] == "flame")
    assert entry["bought"] == 1 and entry["left"] == 4999
    stats = client.get(url + "/analytics", headers=admin).json()
    assert stats["participants"] == 2 and stats["tokens_granted"] == 55
    assert stats["tokens_spent"] == 30 and stats["by_sku"]["flame"] == 1
    # Pausing hides the event and blocks claims; resuming makes version 2.
    client.post(url + "/pause", headers=admin)
    assert quests(client, ana_h)["events"] == []
    assert client.post(url + "/resume", headers=admin).json()["version"] == 2


def test_ended_event_keeps_claims_but_stops_progress(client):
    admin = owner(client)
    ana, ana_h = player(client, "late_ana")
    bo, _ = player(client, "late_bo")
    at = datetime.now(UTC)
    body = {
        "name": "Thử thách cuối tuần",
        "kind": "challenge",
        "start_at": (at - timedelta(days=3)).isoformat(),
        "end_at": (at - timedelta(hours=1)).isoformat(),
        "claim_end_at": (at + timedelta(days=2)).isoformat(),
        "config": {
            "quests": [
                {
                    "key": "WIN",
                    "title": "Thắng 1 trận",
                    "objectives": [{"type": "MATCH_WON", "target": 1}],
                    "rewards": [{"type": "gold", "amount": 300}],
                },
                {
                    "key": "PLAY",
                    "title": "Chơi 1 trận",
                    "objectives": [{"type": "MATCH_COMPLETED", "target": 1}],
                    "rewards": [{"type": "gold", "amount": 100}],
                },
            ]
        },
    }
    created = client.post("/admin/v1/events", json=body, headers=admin).json()
    client.post(f"/admin/v1/events/{created['id']}/publish", headers=admin)
    win_key = liveops.event_quest_key(created["id"], "WIN")
    with db_session() as db:
        db.add(
            liveops.QuestProgress(
                account_id=ana,
                quest_key=win_key,
                period_key="event",
                state=[{"count": 1, "seen": []}],
                status="completed",
                updated_at=at,
            )
        )
        db.commit()
    arena_round(client, "late", 1, [ana, bo], "park", winner=ana)
    event = quests(client, ana_h)["events"][0]
    assert event["window"] == "claim"
    by_key = {q["key"]: q for q in event["quests"]}
    assert by_key[liveops.event_quest_key(created["id"], "PLAY")]["status"] == "expired"
    assert claim(client, ana_h, win_key).status_code == 200


def test_admin_quest_api_requires_admin(client):
    _, headers = player(client, "plain_pilot")
    assert client.get("/admin/v1/quests", headers=headers).status_code == 401
    assert client.get("/v1/quests").status_code in (401, 403)
    admin = owner(client)
    assert client.post("/admin/v1/quests/seed", headers=admin).json()["added"] == 8
    assert client.post("/admin/v1/quests/seed", headers=admin).json()["added"] == 0
    listed = client.get("/admin/v1/quests", headers=admin).json()
    assert [q["key"] for q in listed["quests"]][:2] == ["D01", "D02"]
    assert {r["type"] for r in listed["rules"]} >= {"MATCH_WON", "WITH_FRIEND"}
