from tests.test_liveops import ARENA, INGEST
from tests.test_sync import overrides, player  # noqa: F401


def befriend(client, a_h, b_id, b_h):
    request = client.post("/v1/friends/requests", json={"account_id": b_id}, headers=a_h).json()
    client.post(f"/v1/friends/requests/{request['request_id']}/accept", headers=b_h)


def room(client, room_id, people, phase="waiting", map_id="frost"):
    body = {
        "type": "room",
        "room_id": room_id,
        "process_id": "p1",
        "phase": phase,
        "map_name": "LÂU ĐÀI BĂNG",
        "map_id": map_id,
        "players": [{"account_id": a, "name": f"p{i}"} for i, a in enumerate(people)],
    }
    assert client.post(ARENA, json=body, headers=INGEST).status_code == 204
    return "arena:p1:" + room_id


def test_friend_invite_round_trip(client):
    ana, ana_h = player(client, "inv_ana")
    bo, bo_h = player(client, "inv_bo")
    cu, cu_h = player(client, "inv_cu")
    key = room(client, "r1", [ana])
    body = {"account_id": bo, "room_key": key, "number": 7}
    # Not friends yet: refused.
    assert client.post("/v1/invites", json=body, headers=ana_h).status_code == 403
    befriend(client, ana_h, bo, bo_h)
    friends = client.get("/v1/friends", headers=ana_h).json()["friends"]
    assert friends[0]["online"] is True
    # Only a player seated in the room may invite to it.
    assert client.post("/v1/invites", json=body, headers=bo_h).status_code in (403,)
    sent = client.post("/v1/invites", json=body, headers=ana_h)
    assert sent.status_code == 201 and sent.json()["map_id"] == "frost"
    again = client.post("/v1/invites", json=body, headers=ana_h).json()
    inbox = client.get("/v1/invites", headers=bo_h).json()["invites"]
    assert [i["id"] for i in inbox] == [again["id"]]  # re-invite replaces the old one
    assert inbox[0]["from"]["name"] == "inv_ana" and inbox[0]["number"] == 7
    assert inbox[0]["room_id"] == "r1" and inbox[0]["players"] == 1
    assert client.get("/v1/invites", headers=cu_h).json()["invites"] == []
    assert client.post(f"/v1/invites/{again['id']}/accept", headers=cu_h).status_code == 404
    accepted = client.post(f"/v1/invites/{again['id']}/accept", headers=bo_h)
    assert accepted.status_code == 200 and accepted.json()["status"] == "accepted"
    assert client.post(f"/v1/invites/{again['id']}/accept", headers=bo_h).status_code == 409
    assert client.get("/v1/invites", headers=bo_h).json()["invites"] == []


def test_invites_to_closed_rooms_fail(client):
    ana, ana_h = player(client, "shut_ana")
    bo, bo_h = player(client, "shut_bo")
    befriend(client, ana_h, bo, bo_h)
    key = room(client, "r2", [ana])
    invite = client.post(
        "/v1/invites", json={"account_id": bo, "room_key": key}, headers=ana_h
    ).json()
    room(client, "r2", [ana], phase="playing")
    assert client.post(f"/v1/invites/{invite['id']}/accept", headers=bo_h).status_code == 409
    assert (
        client.post(
            "/v1/invites", json={"account_id": bo, "room_key": key}, headers=ana_h
        ).status_code
        == 409
    )
    room(client, "r3", [ana])
    decline = client.post(
        "/v1/invites", json={"account_id": bo, "room_key": "arena:p1:r3"}, headers=ana_h
    ).json()
    assert client.post(f"/v1/invites/{decline['id']}/decline", headers=bo_h).json()["status"] == (
        "declined"
    )
    # Rate limit: at most 10 invites a minute.
    codes = [
        client.post(
            "/v1/invites", json={"account_id": bo, "room_key": "arena:p1:r3"}, headers=ana_h
        ).status_code
        for _ in range(12)
    ]
    assert codes.count(429) >= 1
