import pytest

from app import main, social


@pytest.fixture(autouse=True)
def no_chat_limit():
    main.app.dependency_overrides[social.check_chat_rate] = lambda: None
    yield


def player(client, name):
    body = {"username": name, "password": "long-enough-password"}
    data = client.post("/v1/register", json=body).json()
    return data["account_id"], {"Authorization": "Bearer " + data["access_token"]}


def test_change_password_needs_current_password(client):
    player(client, "pilot_pw")
    body = {"username": "pilot_pw", "password": "long-enough-password"}
    wrong = {**body, "password": "not-the-password", "new_password": "brand-new-password"}
    assert client.post("/v1/password", json=wrong).status_code == 401
    same = {**body, "new_password": body["password"]}
    assert client.post("/v1/password", json=same).status_code == 422
    short = {**body, "new_password": "short"}
    assert client.post("/v1/password", json=short).status_code == 422
    missing = {**body, "username": "nobody_here", "new_password": "brand-new-password"}
    assert client.post("/v1/password", json=missing).status_code == 401
    changed = client.post("/v1/password", json={**body, "new_password": "brand-new-password"})
    assert changed.status_code == 204
    assert client.post("/v1/login", json=body).status_code == 401
    new_login = {**body, "password": "brand-new-password"}
    assert client.post("/v1/login", json=new_login).status_code == 200


def test_friend_search_request_accept_and_unfriend(client):
    ana, ana_h = player(client, "ana_pilot")
    bo, bo_h = player(client, "bo_pilot")
    guest_h = {"Authorization": "Bearer " + client.post("/v1/guests").json()["access_token"]}
    assert client.get("/v1/users?q=pi", headers=guest_h).status_code == 403
    found = client.get("/v1/users?q=bo_", headers=ana_h).json()["users"]
    assert [user["name"] for user in found] == ["bo_pilot"] and found[0]["relation"] == "none"
    assert client.get("/v1/users?q=%25%25", headers=ana_h).json()["users"] == []
    me_request = {"account_id": ana}
    assert client.post("/v1/friends/requests", json=me_request, headers=ana_h).status_code == 400
    sent = client.post("/v1/friends/requests", json={"account_id": bo}, headers=ana_h)
    assert sent.status_code == 201 and sent.json()["status"] == "pending"
    again = client.post("/v1/friends/requests", json={"account_id": bo}, headers=ana_h)
    assert again.status_code == 409
    assert client.get(f"/v1/users/{bo}", headers=ana_h).json()["relation"] == "outgoing"
    incoming = client.get("/v1/friends", headers=bo_h).json()["incoming"]
    assert incoming[0]["user"]["name"] == "ana_pilot"
    request_id = incoming[0]["request_id"]
    url = f"/v1/friends/requests/{request_id}/accept"
    assert client.post(url, headers=ana_h).status_code == 403
    assert client.post(url, headers=bo_h).json()["status"] == "accepted"
    assert client.get("/v1/friends", headers=ana_h).json()["friends"][0]["name"] == "bo_pilot"
    assert client.delete(f"/v1/friends/{bo}", headers=ana_h).status_code == 204
    assert client.get("/v1/friends", headers=bo_h).json()["friends"] == []


def test_crossed_requests_accept_and_decline_removes(client):
    ana, ana_h = player(client, "ana_pilot")
    bo, bo_h = player(client, "bo_pilot")
    client.post("/v1/friends/requests", json={"account_id": bo}, headers=ana_h)
    back = client.post("/v1/friends/requests", json={"account_id": ana}, headers=bo_h)
    assert back.json()["status"] == "accepted"
    client.delete(f"/v1/friends/{ana}", headers=bo_h)
    request_id = client.post("/v1/friends/requests", json={"account_id": bo}, headers=ana_h).json()[
        "request_id"
    ]
    url = f"/v1/friends/requests/{request_id}/decline"
    assert client.post(url, headers=bo_h).status_code == 204
    assert client.get("/v1/friends", headers=ana_h).json()["outgoing"] == []


def test_chat_channels_respect_membership_and_friendship(client):
    ana, ana_h = player(client, "ana_pilot")
    bo, bo_h = player(client, "bo_pilot")
    cy, cy_h = player(client, "cy_pilot")
    world = client.post("/v1/chat", json={"channel": "world", "body": " xin\nchào "}, headers=ana_h)
    assert world.status_code == 201 and world.json()["body"] == "xin chào"
    blank = client.post("/v1/chat", json={"channel": "world", "body": "\n\t"}, headers=ana_h)
    assert blank.status_code == 422
    long = client.post("/v1/chat", json={"channel": "world", "body": "x" * 201}, headers=ana_h)
    assert long.status_code == 422
    guild_msg = {"channel": "guild", "body": "hi team"}
    assert client.post("/v1/chat", json=guild_msg, headers=ana_h).status_code == 409
    joined = client.post("/v1/guild", json={"name": "  Sóng   Xanh "}, headers=ana_h)
    assert joined.status_code == 201 and joined.json()["guild"]["name"] == "Sóng Xanh"
    same = client.post("/v1/guild", json={"name": "sóng xanh"}, headers=bo_h).json()
    assert same["guild"]["members"] == 2
    assert client.post("/v1/guild", json={"name": "x!"}, headers=cy_h).status_code == 422
    assert client.post("/v1/chat", json=guild_msg, headers=ana_h).status_code == 201
    private = {"channel": "private", "body": "psst", "to": bo}
    assert client.post("/v1/chat", json=private, headers=ana_h).status_code == 403
    client.post("/v1/friends/requests", json={"account_id": bo}, headers=ana_h)
    client.post("/v1/friends/requests", json={"account_id": ana}, headers=bo_h)
    assert client.post("/v1/chat", json=private, headers=ana_h).status_code == 201
    bo_view = [m["body"] for m in client.get("/v1/chat", headers=bo_h).json()["messages"]]
    assert bo_view == ["xin chào", "hi team", "psst"]
    cy_view = [m["body"] for m in client.get("/v1/chat", headers=cy_h).json()["messages"]]
    assert cy_view == ["xin chào"]
    guild_only = client.get("/v1/chat?channel=guild", headers=cy_h).json()["messages"]
    assert guild_only == []
    thread = client.get(f"/v1/chat?channel=private&with={ana}", headers=bo_h).json()["messages"]
    assert thread[0]["sender"]["name"] == "ana_pilot" and thread[0]["to"]["id"] == bo
    after = client.get(f"/v1/chat?after={thread[0]['id']}", headers=bo_h).json()["messages"]
    assert after == []
    assert client.delete("/v1/guild", headers=bo_h).status_code == 204
    assert client.get("/v1/chat?channel=guild", headers=bo_h).json()["messages"] == []
    assert client.get("/v1/guild", headers=bo_h).json() == {"guild": None}


def test_chat_rate_limit_fails_closed(client, monkeypatch):
    main.app.dependency_overrides.pop(social.check_chat_rate)
    _, ana_h = player(client, "ana_pilot")
    message = {"channel": "world", "body": "spam"}
    monkeypatch.setattr(main.limiter, "eval", lambda *args: 6)
    assert client.post("/v1/chat", json=message, headers=ana_h).status_code == 429

    def unavailable(*args):
        raise main.redis.ConnectionError()

    monkeypatch.setattr(main.limiter, "eval", unavailable)
    assert client.post("/v1/chat", json=message, headers=ana_h).status_code == 503
