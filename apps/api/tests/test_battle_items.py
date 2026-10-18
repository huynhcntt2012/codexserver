from tests.test_liveops import ARENA, INGEST
from tests.test_sync import item, overrides, owner, player, service_token  # noqa: F401

LOADOUT = {"Authorization": "Bearer " + service_token()}


def add_battle_items(client, admin):
    for item_id in ("throw_bomb", "dart"):
        body = {
            "id": item_id,
            "name": item_id,
            "category": "consumable",
            "rarity": "common",
            "price": 10,
            "currency": "gold",
            "quantity": 5,
        }
        assert client.post("/admin/v1/items", json=body, headers=admin).status_code == 201
        client.post(f"/admin/v1/items/{item_id}/publish", headers=admin)
    item(client, admin, "pet_bunny", price=1, currency="gold", category="pet")


def test_packs_fill_stock_and_uses_consume_once(client):
    admin = owner(client)
    add_battle_items(client, admin)
    ana, ana_h = player(client, "item_ana")
    buy = {"item_id": "throw_bomb", "request_id": "buy-throw-01"}
    wallet = client.post("/v1/shop/purchase", json=buy, headers=ana_h).json()
    assert wallet["stock"]["throw_bomb"] == 5  # a ×5 pack adds 5 uses
    assert client.get("/v1/catalog").json()["items"][-1]["quantity"] in (1, 5)
    mine = client.get("/v1/inventory/loadout", headers=ana_h).json()
    assert mine["items"]["throw_bomb"] == 5 and mine["items"]["dart"] == 0
    assert mine["slots"][:2] == ["throw_bomb", "dart"] and mine["pet"] is None
    # Practice: the app reports a use; retrying the same request does not consume twice.
    use = {"item_id": "throw_bomb", "request_id": "use-practice-1"}
    assert client.post("/v1/inventory/use", json=use, headers=ana_h).json()["left"] == 4
    assert client.post("/v1/inventory/use", json=use, headers=ana_h).json()["left"] == 4
    empty = {"item_id": "dart", "request_id": "use-practice-2"}
    assert client.post("/v1/inventory/use", json=empty, headers=ana_h).status_code == 409
    # Online: the arena reads the loadout (service token only) and reports uses.
    assert client.get(f"/internal/v1/arena/loadout/{ana}").status_code == 401
    seen = client.get(f"/internal/v1/arena/loadout/{ana}", headers=LOADOUT).json()
    assert seen["items"]["throw_bomb"] == 4
    client.post(
        "/v1/shop/purchase",
        json={"item_id": "pet_bunny", "request_id": "buy-pet-01"},
        headers=ana_h,
    )
    assert client.get(f"/internal/v1/arena/loadout/{ana}", headers=LOADOUT).json()["pet"] == (
        "pet_bunny"
    )
    use_event = {
        "type": "use",
        "room_id": "r1",
        "process_id": "p1",
        "account_id": ana,
        "item_id": "throw_bomb",
        "use_id": "p1.r1.7",
    }
    for _ in range(2):
        assert client.post(ARENA, json=use_event, headers=INGEST).status_code == 204
    assert client.get("/v1/inventory/loadout", headers=ana_h).json()["items"]["throw_bomb"] == 3
    bad = {**use_event, "item_id": "hat_ice"}
    assert client.post(ARENA, json=bad, headers=INGEST).status_code == 422
