from app import economy, main
from tests.test_sync import item, overrides, owner, player  # noqa: F401


def stock(account_id: str, item_id: str) -> int:
    for db in main.app.dependency_overrides[main.db_session]():
        row = db.get(economy.Stock, (account_id, item_id))
        return row.quantity if row else 0


def test_broadcast_with_rewards_claims_once_per_player(client):
    admin = owner(client)
    ana, ana_h = player(client, "mail_ana")
    bo, bo_h = player(client, "mail_bo")
    item(client, admin, "bomb_mail", category="consumable")
    body = {
        "title": "Quà tri ân cộng đồng",
        "body": "Cảm ơn các Boom thủ!",
        "category": "reward",
        "rewards": [
            {"type": "gold", "amount": 2000},
            {"type": "gem", "amount": 50},
            {"type": "item", "item_id": "bomb_mail", "amount": 5},
        ],
    }
    sent = client.post("/admin/v1/mail", json=body, headers=admin)
    assert sent.status_code == 201 and sent.json()["audience"] == "all"
    late, late_h = player(client, "mail_late")  # made after sending: still gets it
    for headers in (ana_h, bo_h, late_h):
        box = client.get("/v1/mail", headers=headers).json()
        assert box["unread"] == 1 and box["claimable"] == 1
    message = client.get("/v1/mail", headers=ana_h).json()["messages"][0]
    assert message["rewards"][2]["amount"] == 5 and message["rewards"][0]["name"] == "Vàng"
    before = client.get("/v1/wallet", headers=ana_h).json()
    claimed = client.post(f"/v1/mail/{message['id']}/claim", headers=ana_h)
    assert claimed.status_code == 200 and claimed.json()["claimed"] and claimed.json()["read"]
    assert client.post(f"/v1/mail/{message['id']}/claim", headers=ana_h).status_code == 409
    after = client.get("/v1/wallet", headers=ana_h).json()
    assert after["gold"] - before["gold"] == 2000 and after["gem"] - before["gem"] == 50
    assert stock(ana, "bomb_mail") == 5
    assert client.post("/v1/mail/claim-all", headers=bo_h).json() == {"claimed": 1}
    assert client.post("/v1/mail/claim-all", headers=bo_h).json() == {"claimed": 0}
    assert stock(bo, "bomb_mail") == 5
    listed = client.get("/admin/v1/mail", headers=admin).json()["messages"][0]
    assert listed["claim_count"] == 2 and listed["read_count"] == 2


def test_targeted_mail_read_delete_and_recall(client):
    admin = owner(client)
    ana, ana_h = player(client, "mail_ana")
    _, bo_h = player(client, "mail_bo")
    note = {"title": "Bảo trì máy chủ", "body": "25/06", "category": "maintenance"}
    assert (
        client.post(
            "/admin/v1/mail", json={**note, "audience": "players"}, headers=admin
        ).status_code
        == 422
    )
    bad = {**note, "audience": "players", "targets": ["nobody"]}
    assert client.post("/admin/v1/mail", json=bad, headers=admin).status_code == 404
    found = client.get("/admin/v1/mail/players?q=mail_an", headers=admin).json()["players"]
    assert [p["id"] for p in found] == [ana]
    sent = client.post(
        "/admin/v1/mail", json={**note, "audience": "players", "targets": [ana]}, headers=admin
    ).json()
    assert client.get("/v1/mail", headers=bo_h).json()["messages"] == []
    box = client.get("/v1/mail", headers=ana_h).json()
    assert box["unread"] == 1 and box["claimable"] == 0
    assert client.post(f"/v1/mail/{sent['id']}/claim", headers=ana_h).status_code == 409
    assert client.post(f"/v1/mail/{sent['id']}/read", headers=bo_h).status_code == 404
    assert client.post(f"/v1/mail/{sent['id']}/read", headers=ana_h).json()["read"] is True
    assert client.get("/v1/mail", headers=ana_h).json()["unread"] == 0
    assert client.post("/v1/mail/delete-read", headers=ana_h).json() == {"deleted": 1}
    assert client.get("/v1/mail", headers=ana_h).json()["messages"] == []

    gift = {"title": "Quà đăng nhập", "rewards": [{"type": "gem", "amount": 10}]}
    gift_id = client.post("/admin/v1/mail", json=gift, headers=admin).json()["id"]
    assert client.delete(f"/v1/mail/{gift_id}", headers=ana_h).status_code == 409  # claim first
    reason = {"reason": "gửi nhầm"}
    assert (
        client.post(f"/admin/v1/mail/{gift_id}/recall", json=reason, headers=admin).json()["phase"]
        == "recalled"
    )
    assert client.get("/v1/mail", headers=bo_h).json()["messages"] == []
    assert client.post(f"/v1/mail/{gift_id}/claim", headers=bo_h).status_code == 404
    assert (
        client.post(
            "/admin/v1/mail",
            json={**gift, "rewards": [{"type": "item", "item_id": "nope"}]},
            headers=admin,
        ).status_code
        == 404
    )
    assert client.post("/admin/v1/mail", json=gift, headers=ana_h).status_code == 401
    actions = [e["action"] for e in client.get("/admin/v1/audit", headers=admin).json()["entries"]]
    assert {"mail.send", "mail.recall"} <= set(actions)
