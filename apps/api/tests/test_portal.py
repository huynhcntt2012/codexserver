from datetime import UTC, datetime, timedelta

from tests.test_liveops import arena_round
from tests.test_sync import overrides, owner, player  # noqa: F401


def test_public_events_need_no_sign_in_and_hide_drafts(client):
    admin = owner(client)
    assert client.get("/v1/public/events").json()["events"] == []
    at = datetime.now(UTC)
    template = {
        "name": "Lễ hội bóng nước",
        "kind": "login",
        "start_at": (at - timedelta(hours=1)).isoformat(),
        "end_at": (at + timedelta(hours=48)).isoformat(),
        "reward_items": [],
    }
    created = client.post("/admin/v1/events", json=template, headers=admin).json()
    assert client.get("/v1/public/events").json()["events"] == []  # still a draft
    client.post(f"/admin/v1/events/{created['id']}/publish", headers=admin)
    reply = client.get("/v1/public/events")
    assert reply.headers["cache-control"].startswith("public")
    event = reply.json()["events"][0]
    assert event["name"] == template["name"] and event["status"] == "live"
    assert "config" not in event and "created_by" not in event


def test_public_rankings_count_verified_online_wins(client):
    ana, _ = player(client, "rank_ana")
    bo, _ = player(client, "rank_bo")
    arena_round(client, "rank1", 1, [ana, bo], winner=ana)
    arena_round(client, "rank1", 2, [ana, bo], winner=ana)
    arena_round(client, "rank1", 3, [bo, ana], winner=bo)
    board = client.get("/v1/public/rankings?period=week").json()
    top = board["players"]
    assert [p["rank"] for p in top] == [1, 2]
    assert top[0]["wins"] == 2 and top[0]["matches"] == 3 and top[1]["wins"] == 1
    assert "account_id" not in top[0]
    assert client.get("/v1/public/rankings?period=all&limit=1").json()["players"][0] == top[0]
    assert client.get("/v1/public/rankings?period=year").status_code == 422
