from app import main
from app.boss import BossRaidMatch, BossRaidParticipant
from tests.test_liveops import arena_round
from tests.test_sync import item, overrides, owner, player  # noqa: F401


def raid(match_id: str, result: str, people: list[str]) -> None:
    from datetime import UTC, datetime

    for db in main.app.dependency_overrides[main.db_session]():
        db.add(
            BossRaidMatch(
                id=match_id,
                event_id="ev",
                room_id="r",
                boss_id="slime_king",
                result=result,
                hp_max=100,
                duration_ms=60_000,
                players=len(people),
                created_at=datetime.now(UTC),
            )
        )
        for account in people:
            db.add(BossRaidParticipant(match_id=match_id, account_id=account, name="x"))
        db.commit()


def test_boards_rank_exp_skin_and_gold_from_server_data(client):
    admin = owner(client)
    ana, ana_h = player(client, "lb_ana")
    bo, bo_h = player(client, "lb_bo")
    arena_round(client, "lb1", 1, [ana, bo], winner=ana)
    arena_round(client, "lb1", 2, [ana, bo], winner=ana)
    raid("p.r.1", "WIN", [bo])
    # A client-reported practice round is not verified: no EXP from it.
    item(client, admin, "hat_lb", category="hat")
    item(client, admin, "bomb_lb", category="consumable")
    for item_id in ("hat_lb", "bomb_lb"):
        grant = {"item_id": item_id, "reason": "test grant"}
        assert client.post(
            f"/admin/v1/accounts/{bo}/inventory", json=grant, headers=admin
        ).is_success
    gold = {"currency": "gold", "delta": 900, "reason": "test gold"}
    assert client.post(f"/admin/v1/accounts/{ana}/wallet", json=gold, headers=admin).is_success

    reply = client.get("/v1/leaderboards", headers=ana_h).json()
    exp = reply["boards"]["exp"]
    # ana: 2 rounds (20) + 2 wins (50) = 140; bo: 2 rounds + raid 30 + raid win 60 = 130.
    assert [(r["rank"], r["name"], r["value"]) for r in exp] == [
        (1, "lb_ana", 140),
        (2, "lb_bo", 130),
    ]
    assert "account_id" not in exp[0] and exp[0]["hero"]
    skin = reply["boards"]["skin"]
    assert [(r["name"], r["value"]) for r in skin] == [("lb_bo", 30)]  # rare hat; bombs skipped
    assert reply["boards"]["gold"][0]["name"] == "lb_ana"
    assert reply["me"]["exp"] == {"rank": 1, "value": 140} and reply["me"]["skin"]["rank"] is None
    assert client.get("/v1/leaderboards").status_code == 401
    assert (
        client.get("/v1/leaderboards?limit=1", headers=bo_h).json()["boards"]["exp"][0]["name"]
        == "lb_ana"
    )


def test_admin_tunes_weights_and_hides_players_with_audit(client):
    admin = owner(client)
    ana, ana_h = player(client, "lb_ana")
    bo, bo_h = player(client, "lb_bo")
    arena_round(client, "lb2", 1, [ana, bo], winner=ana)

    board = client.get("/admin/v1/leaderboards?board=exp", headers=admin).json()
    assert board["rows"][0]["account_id"] == ana and board["rows"][0]["hidden"] is None
    assert client.get("/admin/v1/leaderboards", headers=ana_h).status_code == 401

    current = client.get("/admin/v1/leaderboards/settings", headers=admin).json()
    assert current["exp"]["win"] == 50 and current["defaults"]["skin"]["legendary"] == 100
    body = {"exp": {**current["exp"], "match": 100, "win": 0}, "skin": current["skin"], "size": 20}
    saved = client.put("/admin/v1/leaderboards/settings", json=body, headers=admin).json()
    assert saved["exp"]["match"] == 100 and saved["updated_by"] == "root"
    exp = client.get("/v1/leaderboards", headers=bo_h).json()["boards"]["exp"]
    assert [r["value"] for r in exp] == [100, 100]  # same rounds, no win bonus: name order
    bad = {**body, "size": 1000}
    assert client.put("/admin/v1/leaderboards/settings", json=bad, headers=admin).status_code == 422

    hide = {"reason": "tài khoản thử nghiệm"}
    assert client.post(f"/admin/v1/leaderboards/hidden/{ana}", json=hide, headers=admin).is_success
    reply = client.get("/v1/leaderboards", headers=ana_h).json()
    assert [r["name"] for r in reply["boards"]["exp"]] == ["lb_bo"]
    assert reply["boards"]["exp"][0]["rank"] == 1
    assert reply["me"]["hidden"] is True and reply["me"]["exp"]["rank"] is None
    rows = client.get("/admin/v1/leaderboards?board=exp", headers=admin).json()["rows"]
    hidden_row = next(r for r in rows if r["account_id"] == ana)
    assert hidden_row["rank"] is None and hidden_row["hidden"]["reason"] == hide["reason"]
    listed = client.get("/admin/v1/leaderboards/hidden", headers=admin).json()["players"]
    assert listed[0]["name"] == "lb_ana" and listed[0]["by"] == "root"
    assert (
        client.post("/admin/v1/leaderboards/hidden/nobody", json=hide, headers=admin).status_code
        == 404
    )

    assert client.delete(f"/admin/v1/leaderboards/hidden/{ana}", headers=admin).is_success
    assert client.delete(f"/admin/v1/leaderboards/hidden/{ana}", headers=admin).status_code == 404
    names = [
        r["name"] for r in client.get("/v1/leaderboards", headers=ana_h).json()["boards"]["exp"]
    ]
    assert names == ["lb_ana", "lb_bo"]
    actions = [e["action"] for e in client.get("/admin/v1/audit", headers=admin).json()["entries"]]
    assert {"leaderboard.settings", "leaderboard.hide", "leaderboard.show"} <= set(actions)
