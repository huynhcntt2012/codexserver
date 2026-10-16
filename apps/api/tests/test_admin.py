from datetime import UTC, datetime, timedelta

import pytest

from app import admin_api, admin_auth, main, social

PASSWORD = "admin-password-123"


@pytest.fixture(autouse=True)
def no_admin_limit(monkeypatch):
    main.app.dependency_overrides[admin_auth.check_admin_rate] = lambda: None
    main.app.dependency_overrides[social.check_chat_rate] = lambda: None
    # No arena in unit tests: live rooms report "unavailable" instead of failing.
    monkeypatch.setattr(admin_api, "arena_get", lambda path, token=None: (0, None, 0.0))


def make_admin(client, username="root", role="owner"):
    for db in main.app.dependency_overrides[main.db_session]():
        admin_auth.create_admin(db, username, PASSWORD, role)
        db.commit()
    reply = client.post("/admin/v1/auth/login", json={"username": username, "password": PASSWORD})
    assert reply.status_code == 200
    return {"Authorization": "Bearer " + reply.json()["access_token"]}


def player(client, name="pilot_one"):
    body = {"username": name, "password": "player-password-1"}
    data = client.post("/v1/register", json=body).json()
    return data["account_id"], {"Authorization": "Bearer " + data["access_token"]}


def iso(delta_hours: float) -> str:
    return (datetime.now(UTC) + timedelta(hours=delta_hours)).isoformat()


def new_item(client, headers, item_id="hat_test", publish=True):
    body = {"id": item_id, "name": "Mũ thử", "category": "hat", "rarity": "rare", "price": 90}
    assert client.post("/admin/v1/items", json=body, headers=headers).status_code == 201
    if publish:
        client.post(f"/admin/v1/items/{item_id}/publish", headers=headers)


def test_login_rejects_bad_password_and_player_tokens(client):
    owner = make_admin(client)
    bad = client.post("/admin/v1/auth/login", json={"username": "root", "password": "nope"})
    assert bad.status_code == 401
    _, player_headers = player(client)
    assert client.get("/admin/v1/auth/me", headers=player_headers).status_code == 401
    assert client.get("/admin/v1/accounts").status_code == 401
    me = client.get("/admin/v1/auth/me", headers=owner).json()
    assert me["role"] == "owner" and "admins" in me["permissions"]
    actions = [e["action"] for e in client.get("/admin/v1/audit", headers=owner).json()["entries"]]
    assert "admin.login_failed" in actions and "admin.login" in actions


def test_roles_limit_writes_and_admin_management(client):
    owner = make_admin(client)
    body = {"username": "watcher", "password": PASSWORD, "role": "viewer"}
    assert client.post("/admin/v1/admins", json=body, headers=owner).status_code == 201
    viewer = {
        "Authorization": "Bearer "
        + client.post("/admin/v1/auth/login", json=body).json()["access_token"]
    }
    assert client.get("/admin/v1/items", headers=viewer).status_code == 200
    item = {"id": "x_item", "name": "X item", "category": "pet", "rarity": "common", "price": 1}
    assert client.post("/admin/v1/items", json=item, headers=viewer).status_code == 403
    assert client.get("/admin/v1/admins", headers=viewer).status_code == 403
    admins = client.get("/admin/v1/admins", headers=owner).json()["admins"]
    watcher = next(a for a in admins if a["username"] == "watcher")
    root = next(a for a in admins if a["username"] == "root")
    patch = client.patch(f"/admin/v1/admins/{root['id']}", json={"role": "viewer"}, headers=owner)
    assert patch.status_code == 400
    disabled = client.patch(
        f"/admin/v1/admins/{watcher['id']}", json={"disabled": True}, headers=owner
    )
    assert disabled.json()["disabled"] is True
    assert client.get("/admin/v1/items", headers=viewer).status_code == 401


def test_mfa_setup_then_required_at_login(client):
    owner = make_admin(client)
    setup = client.post("/admin/v1/auth/mfa/setup", headers=owner).json()
    assert setup["uri"].startswith("otpauth://totp/")
    code = admin_auth.totp_code(setup["secret"], int(datetime.now(UTC).timestamp()) // 30)
    bad = client.post("/admin/v1/auth/mfa/enable", json={"otp": "000000"}, headers=owner)
    assert bad.status_code in (200, 400)
    assert client.post("/admin/v1/auth/mfa/enable", json={"otp": code}, headers=owner).json()["mfa"]
    login = {"username": "root", "password": PASSWORD}
    assert client.post("/admin/v1/auth/login", json=login).status_code == 401
    assert client.post("/admin/v1/auth/login", json={**login, "otp": code}).status_code == 200


def test_ban_blocks_login_and_existing_token_until_revoked(client):
    owner = make_admin(client)
    account_id, headers = player(client)
    short = {"reason": "x"}
    assert (
        client.post(f"/admin/v1/accounts/{account_id}/sanctions", json=short, headers=owner)
    ).status_code == 422
    ban = client.post(
        f"/admin/v1/accounts/{account_id}/sanctions",
        json={"reason": "Spam chat thế giới", "hours": 24},
        headers=owner,
    )
    assert ban.status_code == 201 and ban.json()["active"]
    assert client.get("/v1/me", headers=headers).status_code == 403
    login = {"username": "pilot_one", "password": "player-password-1"}
    assert client.post("/v1/login", json=login).status_code == 403
    listed = client.get("/admin/v1/accounts?status=banned", headers=owner).json()
    assert listed["total"] == 1 and listed["items"][0]["banned"]
    revoke = client.post(
        f"/admin/v1/accounts/{account_id}/sanctions/{ban.json()['id']}/revoke",
        json={"reason": "Đã xác minh nhầm"},
        headers=owner,
    )
    assert revoke.json()["active"] is False
    assert client.post("/v1/login", json=login).status_code == 200
    detail = client.get(f"/admin/v1/accounts/{account_id}", headers=owner).json()
    assert detail["sanctions"][0]["revoked_at"] is not None and detail["inventory"]


def test_account_search_grant_and_chat_delete(client):
    owner = make_admin(client)
    account_id, headers = player(client, "searchable_pilot")
    player(client, "other_pilot")
    found = client.get("/admin/v1/accounts?q=searchable", headers=owner).json()
    assert found["total"] == 1 and found["items"][0]["id"] == account_id
    new_item(client, owner)
    grant = {"item_id": "hat_test", "reason": "Bồi thường lỗi"}
    url = f"/admin/v1/accounts/{account_id}/inventory"
    assert client.post(url, json=grant, headers=owner).status_code == 201
    assert client.post(url, json=grant, headers=owner).status_code == 409
    ledger = client.get("/admin/v1/economy", headers=owner).json()
    assert ledger["wallets"] is False and ledger["entries"][0]["item"] == "hat_test"
    client.post("/v1/chat", json={"channel": "world", "body": "quảng cáo"}, headers=headers)
    message = client.get(f"/admin/v1/accounts/{account_id}", headers=owner).json()["messages"][0]
    deleted = client.post(
        f"/admin/v1/chat/{message['id']}/delete", json={"reason": "Quảng cáo"}, headers=owner
    )
    assert deleted.status_code == 200
    assert client.get(f"/admin/v1/accounts/{account_id}", headers=owner).json()["messages"] == []


def test_item_and_event_lifecycle(client):
    owner = make_admin(client)
    new_item(client, owner, publish=False)
    items = client.get("/admin/v1/items?status=draft", headers=owner).json()["items"]
    assert [i["id"] for i in items] == ["hat_test"]
    patched = client.patch("/admin/v1/items/hat_test", json={"price": 120}, headers=owner)
    assert patched.json()["price"] == 120
    assert client.post("/admin/v1/items/hat_test/publish", headers=owner).json()["status"] == (
        "published"
    )
    event = {
        "name": "Lễ hội bóng nước",
        "kind": "login",
        "start_at": iso(-1),
        "end_at": iso(48),
        "reward_items": ["hat_test"],
    }
    bad = {**event, "end_at": iso(-2)}
    assert client.post("/admin/v1/events", json=bad, headers=owner).status_code == 422
    missing = {**event, "reward_items": ["nope"]}
    assert client.post("/admin/v1/events", json=missing, headers=owner).status_code == 422
    created = client.post("/admin/v1/events", json=event, headers=owner).json()
    assert created["phase"] == "draft"
    url = f"/admin/v1/events/{created['id']}"
    assert client.post(url + "/publish", headers=owner).json()["phase"] == "running"
    assert client.put(url, json=event, headers=owner).status_code == 409
    assert client.post(url + "/pause", headers=owner).json()["phase"] == "paused"
    assert client.put(url, json={**event, "name": "Lễ hội mới"}, headers=owner).status_code == 200
    assert client.post(url + "/resume", headers=owner).json()["phase"] == "running"
    overview = client.get("/admin/v1/reports/overview", headers=owner).json()
    assert overview["liveops"]["events_running"] == 1 and overview["revenue"] is None


def test_giftcode_redeem_once_per_account_and_quota(client):
    owner = make_admin(client)
    new_item(client, owner)
    body = {
        "code": "bup-test-1",
        "name": "Quà thử",
        "reward_items": ["hat_test"],
        "max_redemptions": 1,
        "expires_at": iso(24),
    }
    created = client.post("/admin/v1/giftcodes", json=body, headers=owner).json()
    assert created["code"] == "BUP-TEST-1" and created["phase"] == "active"
    assert client.post("/admin/v1/giftcodes", json=body, headers=owner).status_code == 409
    random = client.post("/admin/v1/giftcodes", json={**body, "code": None}, headers=owner).json()
    assert random["code"].startswith("BUP-")
    ana, ana_h = player(client, "ana_pilot")
    _, bo_h = player(client, "bo_pilot")
    redeemed = client.post("/v1/giftcodes/redeem", json={"code": "bup-test-1"}, headers=ana_h)
    assert redeemed.json()["granted"] == ["hat_test"]
    again = client.post("/v1/giftcodes/redeem", json={"code": "BUP-TEST-1"}, headers=ana_h)
    assert again.status_code == 409
    full = client.post("/v1/giftcodes/redeem", json={"code": "BUP-TEST-1"}, headers=bo_h)
    assert full.status_code == 409 and "exhausted" in full.json()["detail"]
    client.post(f"/admin/v1/giftcodes/{random['id']}/disable", headers=owner)
    off = client.post("/v1/giftcodes/redeem", json={"code": random["code"]}, headers=bo_h)
    assert off.status_code == 409
    users = client.get(f"/admin/v1/giftcodes/{created['id']}/redemptions", headers=owner).json()
    assert users["redemptions"][0]["account_id"] == ana


def test_shop_offer_needs_published_item_and_lists_publicly(client):
    owner = make_admin(client)
    new_item(client, owner, publish=False)
    offer = {"item_id": "hat_test", "price": 200, "currency": "gem", "discount_percent": 25}
    created = client.post("/admin/v1/shop/offers", json=offer, headers=owner).json()
    assert created["final_price"] == 150
    url = f"/admin/v1/shop/offers/{created['id']}/publish"
    assert client.post(url, headers=owner).status_code == 409
    client.post("/admin/v1/items/hat_test/publish", headers=owner)
    assert client.post(url, headers=owner).json()["phase"] == "on_sale"
    public = client.get("/v1/shop/offers").json()["offers"]
    assert [o["item_id"] for o in public] == ["hat_test"]


def test_server_and_live_rooms_report_arena_down(client):
    owner = make_admin(client)
    assert client.get("/admin/v1/rooms/live", headers=owner).json()["available"] is False
    checks = {
        c["name"]: c["ok"] for c in client.get("/admin/v1/server", headers=owner).json()["checks"]
    }
    assert checks["Account API"] and checks["Arena (Colyseus)"] is False
