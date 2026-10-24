import struct
import zlib
from datetime import UTC, datetime, timedelta

import jwt
import pytest

from app import admin_api, admin_auth, main, social

PASSWORD = "admin-password-123"


@pytest.fixture(autouse=True)
def overrides(monkeypatch):
    main.app.dependency_overrides[admin_auth.check_admin_rate] = lambda: None
    main.app.dependency_overrides[social.check_chat_rate] = lambda: None
    monkeypatch.setattr(admin_api, "arena_get", lambda path, token=None: (0, None, 0.0))


def png(size=32, shade=0) -> bytes:
    raw = b"".join(b"\x00" + bytes([shade, 100, 200, 255]) * size for _ in range(size))
    chunk = lambda kind, data: (  # noqa: E731
        struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    )
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw))
        + chunk(b"IEND", b"")
    )


def owner(client):
    for db in main.app.dependency_overrides[main.db_session]():
        admin_auth.create_admin(db, "root", PASSWORD, "owner")
        db.commit()
    token = client.post(
        "/admin/v1/auth/login", json={"username": "root", "password": PASSWORD}
    ).json()["access_token"]
    return {"Authorization": "Bearer " + token}


def player(client, name="pilot_one"):
    body = {"username": name, "password": "player-password-1"}
    data = client.post("/v1/register", json=body).json()
    return data["account_id"], {"Authorization": "Bearer " + data["access_token"]}


def item(client, admin, item_id="hat_sync", price=90, currency="gem", category="hat"):
    body = {
        "id": item_id,
        "name": "Mũ đồng bộ",
        "category": category,
        "rarity": "rare",
        "price": price,
        "currency": currency,
        "icon": "items/heart.png",
    }
    assert client.post("/admin/v1/items", json=body, headers=admin).status_code == 201
    client.post(f"/admin/v1/items/{item_id}/publish", headers=admin)


def test_wallet_welcome_topup_exchange_and_idempotency(client):
    _, headers = player(client)
    wallet = client.get("/v1/wallet", headers=headers).json()
    assert (wallet["gold"], wallet["gem"]) == (5000, 100)
    assert "outfit_mimi" in wallet["owned"]
    packs = client.get("/v1/topup/packs").json()
    assert packs["sandbox"] is True
    body = {"pack_id": "gem_60", "request_id": "tap-0000001"}
    assert client.post("/v1/topup", json=body, headers=headers).json()["gem"] == 160
    assert client.post("/v1/topup", json=body, headers=headers).json()["gem"] == 160
    exchange = {"pack_id": "gold_5000", "request_id": "tap-0000002"}
    after = client.post("/v1/topup", json=exchange, headers=headers).json()
    assert (after["gold"], after["gem"]) == (10000, 110)
    kinds = [e["kind"] for e in client.get("/v1/wallet/ledger", headers=headers).json()["entries"]]
    assert kinds.count("topup") == 1 and kinds.count("exchange") == 2 and "welcome" in kinds


def test_purchase_is_server_priced_with_offer_and_balance_checks(client):
    admin = owner(client)
    item(client, admin, price=90)
    item(client, admin, "potion_sync", price=40, currency="gem", category="consumable")
    offer = {"item_id": "hat_sync", "price": 90, "currency": "gem", "discount_percent": 50}
    created = client.post("/admin/v1/shop/offers", json=offer, headers=admin).json()
    client.post(f"/admin/v1/shop/offers/{created['id']}/publish", headers=admin)
    _, headers = player(client)
    bought = client.post(
        "/v1/shop/purchase",
        json={"item_id": "hat_sync", "request_id": "buy-0000001"},
        headers=headers,
    ).json()
    assert bought["gem"] == 100 - 45 and "hat_sync" in bought["owned"]
    again = client.post(
        "/v1/shop/purchase",
        json={"item_id": "hat_sync", "request_id": "buy-0000002"},
        headers=headers,
    )
    assert again.status_code == 409
    body = {"item_id": "potion_sync", "request_id": "buy-potion-1"}
    stock = client.post("/v1/shop/purchase", json=body, headers=headers).json()
    assert stock["stock"] == {"potion_sync": 1} and stock["gem"] == 15
    poor = client.post(
        "/v1/shop/purchase",
        json={"item_id": "potion_sync", "request_id": "buy-potion-9"},
        headers=headers,
    )
    assert poor.status_code == 409


def test_catalog_etag_assets_and_icon_upload(client):
    admin = owner(client)
    item(client, admin)
    assert (
        client.post("/admin/v1/items/hat_sync/icon", content=b"nope", headers=admin).status_code
        == 422
    )
    uploaded = client.post("/admin/v1/items/hat_sync/icon", content=png(), headers=admin).json()
    sha = uploaded["icon_sha256"]
    catalog = client.get("/v1/catalog")
    entry = next(i for i in catalog.json()["items"] if i["id"] == "hat_sync")
    assert entry["icon_url"] == f"/v1/assets/{sha}.png" and entry["icon"] == "items/heart.png"
    etag = catalog.headers["etag"]
    assert client.get("/v1/catalog", headers={"If-None-Match": etag}).status_code == 304
    art = client.get(entry["icon_url"])
    assert art.content == png() and "immutable" in art.headers["cache-control"]
    assert client.get("/v1/assets/" + "0" * 64 + ".png").status_code == 404
    client.post("/admin/v1/items/hat_sync/icon", content=png(shade=9), headers=admin)
    changed = client.get("/v1/catalog", headers={"If-None-Match": etag})
    assert changed.status_code == 200 and changed.headers["etag"] != etag


def test_icon_upload_allows_large_png_up_to_10_mb(client):
    admin = owner(client)
    item(client, admin)
    url = "/admin/v1/items/hat_sync/icon"
    # A 2048 px PNG of about 1.5 MB (the old 512 KB / 1024 px limits rejected it).
    big = png(size=2048)
    big = big[:-12] + _text_chunk(1_500_000) + big[-12:]
    assert len(big) > 1_500_000
    ok = client.post(url, content=big, headers=admin)
    assert ok.status_code == 200, ok.text
    assert client.get(f"/v1/assets/{ok.json()['icon_sha256']}.png").content == big
    assert client.post(url, content=png(size=2049), headers=admin).status_code == 422
    huge = big[:-12] + _text_chunk(10 * 1024 * 1024) + big[-12:]
    assert client.post(url, content=huge, headers=admin).status_code == 413


def _text_chunk(length: int) -> bytes:
    data = b"Comment\x00" + b"x" * length
    return (
        struct.pack(">I", len(data))
        + b"tEXt"
        + data
        + struct.pack(">I", zlib.crc32(b"tEXt" + data))
    )


def test_admin_accounts_status_presence_edit_and_wallet(client):
    admin = owner(client)
    account_id, headers = player(client)
    client.get("/v1/wallet", headers=headers)
    row = client.get("/admin/v1/accounts?q=pilot_one", headers=admin).json()["items"][0]
    assert row["status"] == "active" and row["online"] and row["gold"] == 5000 and row["items"] >= 4
    assert client.get("/admin/v1/accounts?status=online", headers=admin).json()["total"] == 1
    ban = client.post(
        f"/admin/v1/accounts/{account_id}/sanctions",
        json={"reason": "Kiểm tra trạng thái"},
        headers=admin,
    ).json()
    client.post(
        f"/admin/v1/accounts/{account_id}/sanctions/{ban['id']}/revoke",
        json={"reason": "Đã xong kiểm tra"},
        headers=admin,
    )
    unlocked = client.get("/admin/v1/accounts?status=unlocked", headers=admin).json()
    assert unlocked["total"] == 1 and unlocked["items"][0]["status"] == "unlocked"
    edit = {
        "display_name": "Pilot Mới",
        "email": "Pilot@Example.com",
        "reason": "Người chơi yêu cầu",
    }
    edited = client.patch(f"/admin/v1/accounts/{account_id}", json=edit, headers=admin).json()
    assert edited["name"] == "Pilot Mới" and edited["email"] == "pilot@example.com"
    url = f"/admin/v1/accounts/{account_id}/wallet"
    too_much = {"currency": "gem", "delta": -1000, "reason": "Thu hồi lỗi"}
    assert client.post(url, json=too_much, headers=admin).status_code == 409
    adjust = {"currency": "gem", "delta": 25, "reason": "Bồi thường bảo trì"}
    assert client.post(url, json=adjust, headers=admin).json()["gem"] == 125
    detail = client.get(f"/admin/v1/accounts/{account_id}", headers=admin).json()
    assert detail["ledger"][0]["kind"] == "admin_adjust" and detail["ledger"][0]["actor"] == "root"
    client.post(
        "/v1/topup", json={"pack_id": "gem_330", "request_id": "tap-0000009"}, headers=headers
    )
    tx = client.get("/admin/v1/transactions?kind=topup", headers=admin).json()
    assert tx["total"] == 1 and tx["items"][0]["account_name"] == "Pilot Mới"
    assert tx["summary"]["sandbox_vnd"] == 99_000 and tx["summary"]["gem_topped_up"] == 330
    overview = client.get("/admin/v1/reports/overview", headers=admin).json()
    assert overview["online_now"] == 1


def service_token(audience="suni-ingest"):
    issued = datetime.now(UTC)
    return jwt.encode(
        {"iss": "suni-arena", "aud": audience, "iat": issued, "exp": issued + timedelta(minutes=1)},
        main.JWT_SECRET,
        algorithm="HS256",
    )


def test_arena_ingestion_is_authenticated_and_idempotent(client):
    admin = owner(client)
    ana, _ = player(client, "ana_pilot")
    bo, _ = player(client, "bo_pilot")
    url = "/internal/v1/arena/events"
    room = {
        "type": "room",
        "room_id": "abc123",
        "process_id": "p1",
        "players": [
            {"account_id": ana, "name": "ana_pilot"},
            {"account_id": bo, "name": "bo_pilot"},
        ],
    }
    assert client.post(url, json=room).status_code == 401
    bad = {"Authorization": "Bearer " + service_token("suni-arena")}
    assert client.post(url, json=room, headers=bad).status_code == 401
    ok = {"Authorization": "Bearer " + service_token()}
    assert client.post(url, json=room, headers=ok).status_code == 204
    playing = {**room, "phase": "playing"}
    client.post(url, json=playing, headers=ok)
    match = {
        **room,
        "type": "match",
        "round": 1,
        "duration_ms": 42000,
        "results": [
            {
                "account_id": ana,
                "name": "ana_pilot",
                "placement": 1,
                "kills": 1,
                "bombs": 6,
                "winner": True,
            },
            {"account_id": bo, "name": "bo_pilot", "placement": 2, "bombs": 3},
        ],
    }
    client.post(url, json=match, headers=ok)
    client.post(url, json=match, headers=ok)
    rooms = client.get("/admin/v1/rooms", headers=admin).json()
    assert rooms["summary"]["playing"] == 1 and rooms["items"][0]["creator_name"] == "ana_pilot"
    history = client.get("/admin/v1/matches", headers=admin).json()
    assert history["total"] == 1 and history["items"][0]["verified"] is True
    people = history["items"][0]["participants"]
    assert [p["name"] for p in people] == ["ana_pilot", "bo_pilot"] and people[0]["winner"]
    client.post(url, json={**room, "type": "closed"}, headers=ok)
    assert client.get("/admin/v1/rooms?status=closed", headers=admin).json()["total"] == 1
    stats = client.get(f"/admin/v1/accounts/{ana}", headers=admin).json()["stats"]
    assert stats == {"matches": 1, "wins": 1, "kills": 1, "rooms_created": 1}
    # v1 rooms default to the original map; v2 rooms report their own map.
    assert rooms["items"][0]["map_name"] == "Neon Garden"
    v2 = {**room, "room_id": "v2room", "map_name": "LÂU ĐÀI BĂNG"}
    assert client.post(url, json=v2, headers=ok).status_code == 204
    summary = client.get("/v1/rooms/summary").json()
    frost = next(m for m in summary["maps"] if m["name"] == "LÂU ĐÀI BĂNG")
    assert frost["players"] == 2 and frost["waiting"] == 1


def test_practice_reports_are_unverified_and_trust_only_the_token(client):
    admin = owner(client)
    account_id, headers = player(client)
    other, _ = player(client, "other_pilot")
    room = client.post(
        "/v1/practice/rooms", json={"map_name": "Công Viên Kẹo"}, headers=headers
    ).json()
    base = f"/v1/practice/rooms/{room['room_id']}"
    client.post(base + "/state", json={"status": "playing"}, headers=headers)
    result = {
        "round": 1,
        "duration_ms": 61000,
        "participants": [
            {"account_id": other, "name": "pilot_one", "placement": 1, "kills": 3, "winner": True},
            {"name": "Bot Kai", "is_bot": True, "hero": "kai", "placement": 2},
        ],
    }
    assert client.post(base + "/matches", json=result, headers=headers).status_code == 201
    two_humans = {**result, "round": 2, "participants": [result["participants"][0]] * 2}
    assert client.post(base + "/matches", json=two_humans, headers=headers).status_code == 422
    _, stranger = player(client, "stranger_pilot")
    assert (
        client.post(base + "/state", json={"status": "closed"}, headers=stranger).status_code == 404
    )
    match = client.get("/admin/v1/matches?source=practice", headers=admin).json()["items"][0]
    assert match["verified"] is False and match["participants"][0]["account_id"] == account_id
    assert client.get(f"/admin/v1/matches?account_id={other}", headers=admin).json()["total"] == 0


def test_room_chat_is_limited_to_room_members(client):
    _, host = player(client, "room_host")
    other_id, other = player(client, "room_guest")
    room = client.post("/v1/practice/rooms", json={"map_name": "Đảo"}, headers=host).json()
    key = room["room_key"]
    hello = {"channel": "room", "room": key, "body": "chào cả phòng"}
    assert client.post("/v1/chat", json=hello, headers=host).status_code == 201
    assert client.post("/v1/chat", json=hello, headers=other).status_code == 403
    assert client.post("/v1/chat", json={**hello, "room": None}, headers=host).status_code == 403
    seen = client.get(f"/v1/chat?channel=room&room={key}", headers=host).json()["messages"]
    assert [m["body"] for m in seen] == ["chào cả phòng"]
    assert client.get(f"/v1/chat?channel=room&room={key}", headers=other).status_code == 403
    # Room lines never leak into the lobby "all" feed.
    assert client.get("/v1/chat", headers=host).json()["messages"] == []
    # Arena players become members when the room reports them.
    issued = datetime.now(UTC)
    token = jwt.encode(
        {
            "iss": "suni-arena",
            "aud": "suni-ingest",
            "iat": issued,
            "exp": issued + timedelta(minutes=1),
        },
        main.JWT_SECRET,
        algorithm="HS256",
    )
    event = {
        "type": "room",
        "room_id": "r1",
        "process_id": "p9",
        "players": [{"account_id": other_id, "name": "room_guest"}],
    }
    client.post(
        "/internal/v1/arena/events", json=event, headers={"Authorization": "Bearer " + token}
    )
    arena = {"channel": "room", "room": "arena:p9:r1", "body": "gg"}
    assert client.post("/v1/chat", json=arena, headers=other).status_code == 201
    assert client.post("/v1/chat", json=arena, headers=host).status_code == 403


def test_public_room_summary_counts_people_per_map(client):
    _, host = player(client, "summary_host")
    _, other = player(client, "summary_other")
    one = client.post("/v1/practice/rooms", json={"map_name": "Đảo Nắng Vàng"}, headers=host).json()
    client.post("/v1/practice/rooms", json={"map_name": "đảo nắng vàng"}, headers=other)
    client.post(
        f"/v1/practice/rooms/{one['room_id']}/state", json={"status": "playing"}, headers=host
    )
    closed = client.post("/v1/practice/rooms", json={"map_name": "Lâu Đài"}, headers=other).json()
    client.post(
        f"/v1/practice/rooms/{closed['room_id']}/state", json={"status": "closed"}, headers=other
    )
    summary = client.get("/v1/rooms/summary").json()
    assert summary["players"] == 2 and summary["rooms"] == 2
    island = summary["maps"][0]
    assert (island["players"], island["waiting"], island["playing"]) == (2, 1, 1)


def test_player_renames_display_name(client):
    _, headers = player(client, "rename_me")
    renamed = client.patch("/v1/me", json={"display_name": "  Bụp   Siêu Cấp "}, headers=headers)
    assert renamed.status_code == 200 and renamed.json()["name"] == "Bụp Siêu Cấp"
    assert client.get("/v1/me", headers=headers).json()["name"] == "Bụp Siêu Cấp"
    for bad in ["x", "<script>", "a" * 25]:
        assert (
            client.patch("/v1/me", json={"display_name": bad}, headers=headers).status_code == 422
        )
    login = {"username": "rename_me", "password": "player-password-1"}
    assert client.post("/v1/login", json=login).json()["name"] == "Bụp Siêu Cấp"


def test_arena_room_survives_a_concurrent_insert(client):
    from sqlalchemy.orm import Session

    from app import matches

    event = matches.ArenaEvent(type="room", room_id="race1", process_id="p1")
    engine = next(main.app.dependency_overrides[main.db_session]()).get_bind()
    with Session(engine) as first:
        matches.arena_room(first, event)
        first.commit()
    with Session(engine) as second:
        real_get = second.get
        calls = []

        def stale_get(model, key):
            calls.append(key)
            # The first lookup misses, as if another event had not committed yet.
            return None if len(calls) == 1 else real_get(model, key)

        second.get = stale_get
        room = matches.arena_room(second, event)
        second.commit()
        assert room.id == "arena:p1:race1" and len(calls) == 2
