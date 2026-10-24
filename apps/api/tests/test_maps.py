import copy

from app.maps import TEMPLATE
from tests.test_sync import overrides, owner, player  # noqa: F401 (autouse fixture)


def body(**changes):
    data = copy.deepcopy(TEMPLATE)
    data.update(changes)
    return data


def test_template_validates_and_publishes_as_a_level(client):
    admin = owner(client)
    template = client.get("/admin/v1/maps/template", headers=admin).json()
    assert template["template"]["id"] == "candy_maze" and "pastry" in template["art"]["floor"]
    checked = client.post("/admin/v1/maps/validate", json=body(), headers=admin).json()
    assert checked["ok"] and checked["errors"] == []
    created = client.post("/admin/v1/maps", json=body(), headers=admin)
    assert created.status_code == 201 and created.json()["status"] == "draft"
    assert client.post("/admin/v1/maps", json=body(), headers=admin).status_code == 409
    # Drafts are not public.
    assert client.get("/v1/maps").json()["maps"] == []
    client.post("/admin/v1/maps/candy_maze/publish", headers=admin)
    public = client.get("/v1/maps")
    level = public.json()["maps"][0]
    assert level["id"] == "candy_maze" and level["name"] == "MÊ CUNG KẸO"
    assert level["subtitle"] == "Trung bình • Khu vườn kẹo"
    assert (level["columns"], level["rows"]) == (17, 13)
    assert level["spawns"] == [[1, 1], [15, 1], [15, 11], [1, 11]]
    assert len(level["arena_spawns"]) == 8 and level["theme"] == "pastry"
    etag = public.headers["etag"]
    assert client.get("/v1/maps", headers={"If-None-Match": etag}).status_code == 304
    # Editing bumps the revision and the public version; hiding removes it.
    edited = client.put(
        "/admin/v1/maps/candy_maze", json=body(name="Mê Cung Kẹo 2"), headers=admin
    ).json()
    assert edited["revision"] == 2
    assert client.get("/v1/maps", headers={"If-None-Match": etag}).status_code == 200
    client.post("/admin/v1/maps/candy_maze/hide", headers=admin)
    assert client.get("/v1/maps").json()["maps"] == []
    listed = client.get("/admin/v1/maps", headers=admin).json()
    assert listed["maps"][0]["status"] == "hidden" and "moon" in listed["builtin"]


def test_bad_maps_are_refused_with_reasons(client):
    admin = owner(client)
    url = "/admin/v1/maps/validate"

    def errors(**changes):
        result = client.post(url, json=body(**changes), headers=admin).json()
        assert result["ok"] is False, result
        return " ".join(result["errors"])

    assert "trùng" in errors(id="moon")
    rows = list(TEMPLATE["layout"])
    assert "dài bằng nhau" in errors(layout=rows[:-1] + ["#" * 16])
    assert "Ký tự" in errors(layout=[r.replace("C", "X") for r in rows])
    assert "Kích thước" in errors(layout=[r[:-1] for r in rows])
    assert "Viền" in errors(layout=[rows[0]] + ["." + r[1:] for r in rows[1:-1]] + [rows[-1]])
    blocked = list(rows)
    blocked[1] = "##" + blocked[1][2:]
    assert "xuất phát" in errors(layout=blocked)
    walled = [r[:4] + "#" + r[5:] for r in rows]  # a wall column cuts left from right
    assert "chia cắt" in errors(layout=walled)
    assert "art.floor" in errors(art={**TEMPLATE["art"], "floor": "rainbow"})
    # Crates next to a start are cleared (warned), not refused.
    crowded = list(rows)
    crowded[1] = "#..CC.C...C.C...#"
    result = client.post(url, json=body(layout=crowded), headers=admin).json()
    assert result["ok"] and any("dọn" in w for w in result["warnings"])
    assert result["layout"][1][3] == "."
    refused = client.post("/admin/v1/maps", json=body(layout=walled), headers=admin)
    assert refused.status_code == 422 and refused.json()["detail"]["errors"]


def test_only_admins_write_maps(client):
    _, headers = player(client, "map_player")
    assert client.post("/admin/v1/maps", json=body(), headers=headers).status_code == 401
    assert client.get("/admin/v1/maps").status_code == 401
    assert client.get("/v1/maps").status_code == 200
