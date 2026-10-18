import json
from datetime import UTC, datetime, timedelta

from tests.test_admin import PASSWORD, make_admin
from tests.test_sync import overrides, png  # noqa: F401


def viewer_of(client, owner):
    body = {"username": "web_viewer", "password": PASSWORD, "role": "viewer"}
    assert client.post("/admin/v1/admins", json=body, headers=owner).status_code == 201
    token = client.post("/admin/v1/auth/login", json=body).json()["access_token"]
    return {"Authorization": "Bearer " + token}


def post(slug="tin-moi", **extra):
    return {
        "slug": slug,
        "title": "Tin mới‮ từ BỤP BỤP!",
        "category": "Cập nhật",
        "excerpt": "Tóm tắt  <b>ngắn</b>\x00",
        "body": ["Đoạn một.", "  ", "<script>alert(1)</script>"],
        "image": "/img/news-maps.webp",
        "publish_at": (datetime.now(UTC) - timedelta(hours=1)).isoformat(),
        **extra,
    }


def audit_actions(client, owner):
    return [row["action"] for row in client.get("/admin/v1/audit", headers=owner).json()["entries"]]


def test_news_lifecycle_drafts_schedule_and_public_reads(client):
    owner = make_admin(client)
    assert client.get("/v1/public/news").json() == {"news": []}
    created = client.post("/admin/v1/website/news", json=post(), headers=owner)
    assert created.status_code == 201
    news = created.json()
    # Plain text only: control/bidi characters gone, markup kept as inert text.
    assert news["title"] == "Tin mới từ BỤP BỤP!"
    assert news["excerpt"] == "Tóm tắt <b>ngắn</b>"
    assert news["body"] == ["Đoạn một.", "<script>alert(1)</script>"]
    assert news["status"] == "draft"
    assert client.get("/v1/public/news").json()["news"] == []
    assert client.get("/v1/public/news/tin-moi").status_code == 404

    client.post(f"/admin/v1/website/news/{news['id']}/publish", headers=owner)
    reply = client.get("/v1/public/news")
    assert reply.headers["cache-control"].startswith("public")
    listed = reply.json()["news"]
    assert [n["slug"] for n in listed] == ["tin-moi"] and "body" not in listed[0]
    assert "id" not in listed[0] and "created_by" not in listed[0]
    detail = client.get("/v1/public/news/tin-moi").json()
    assert detail["body"] == news["body"] and detail["category"] == "Cập nhật"

    # A pinned post comes first; a future publish date stays hidden until then.
    later = (datetime.now(UTC) + timedelta(days=2)).isoformat()
    pinned = client.post(
        "/admin/v1/website/news",
        json=post("ghim", pinned=True, category="Sự kiện", publish_at=later),
        headers=owner,
    ).json()
    client.post(f"/admin/v1/website/news/{pinned['id']}/publish", headers=owner)
    assert client.get("/admin/v1/website/news", headers=owner).json()["news"][0]["phase"] == (
        "scheduled"
    )
    assert [n["slug"] for n in client.get("/v1/public/news").json()["news"]] == ["tin-moi"]
    earlier = (datetime.now(UTC) - timedelta(minutes=5)).isoformat()
    edited = client.put(
        f"/admin/v1/website/news/{pinned['id']}",
        json=post("ghim", pinned=True, category="Sự kiện", publish_at=earlier),
        headers=owner,
    )
    assert edited.status_code == 200
    assert [n["slug"] for n in client.get("/v1/public/news").json()["news"]] == ["ghim", "tin-moi"]
    events = client.get("/v1/public/news?category=Sự kiện").json()["news"]
    assert [n["slug"] for n in events] == ["ghim"]

    client.post(f"/admin/v1/website/news/{news['id']}/unpublish", headers=owner)
    assert client.get("/v1/public/news/tin-moi").status_code == 404
    assert client.delete(f"/admin/v1/website/news/{news['id']}", headers=owner).status_code == 200
    assert client.delete(f"/admin/v1/website/news/{news['id']}", headers=owner).status_code == 404

    actions = audit_actions(client, owner)
    for action in (
        "website.news_create",
        "website.news_publish",
        "website.news_update",
        "website.news_unpublish",
        "website.news_delete",
    ):
        assert action in actions


def test_news_validation_rejects_bad_slug_image_and_duplicates(client):
    owner = make_admin(client)
    url = "/admin/v1/website/news"
    assert client.post(url, json=post(), headers=owner).status_code == 201
    assert client.post(url, json=post(), headers=owner).status_code == 409
    for bad in (
        post("Bad Slug"),
        post("x-1", image="javascript:alert(1)"),
        post("x-2", image="https://evil.example/a.webp"),
        post("x-3", image="/img/../../etc.webp"),
        post("x-4", category="Khác"),
        post("x-5", body=["   ", "\x00"]),
        post("x-6", title="  ​ a "),
    ):
        assert client.post(url, json=bad, headers=owner).status_code == 422, bad["slug"]
    other = client.post(url, json=post("bai-khac"), headers=owner).json()
    renamed = client.put(f"{url}/{other['id']}", json=post("tin-moi"), headers=owner)
    assert renamed.status_code == 409


def test_viewer_reads_but_cannot_edit_website(client):
    owner = make_admin(client)
    viewer = viewer_of(client, owner)
    created = client.post("/admin/v1/website/news", json=post(), headers=owner).json()
    assert client.get("/admin/v1/website/news", headers=viewer).status_code == 200
    assert client.get("/admin/v1/website/site", headers=viewer).status_code == 200
    assert client.get("/admin/v1/website/releases", headers=viewer).status_code == 200
    denied = [
        client.post("/admin/v1/website/news", json=post("v"), headers=viewer),
        client.put(f"/admin/v1/website/news/{created['id']}", json=post(), headers=viewer),
        client.post(f"/admin/v1/website/news/{created['id']}/publish", headers=viewer),
        client.delete(f"/admin/v1/website/news/{created['id']}", headers=viewer),
        client.put("/admin/v1/website/site", json={}, headers=viewer),
        client.post("/admin/v1/website/images", content=png(), headers=viewer),
    ]
    assert [r.status_code for r in denied] == [403] * len(denied)
    assert client.get("/admin/v1/website/news").status_code == 401


def test_hero_defaults_edit_and_audit(client):
    owner = make_admin(client)
    hero = client.get("/v1/public/site").json()["hero"]
    assert hero["headline"] == "Đặt bom nước" and hero["cta_demo"] == "Chơi demo"
    body = {
        "headline": "  Mùa hè\n bóng nước ",
        "headline_accent": "Nổ tung cùng bạn!",
        "subline": "6 vật phẩm mới",
        "cta_download": "Tải ngay",
        "cta_demo": "Chơi thử",
    }
    saved = client.put("/admin/v1/website/site", json=body, headers=owner)
    assert saved.status_code == 200 and saved.json()["updated_by"] == "root"
    hero = client.get("/v1/public/site").json()["hero"]
    assert hero["headline"] == "Mùa hè bóng nước" and hero["cta_download"] == "Tải ngay"
    assert (
        client.put(
            "/admin/v1/website/site", json={**body, "cta_demo": " "}, headers=owner
        ).status_code
        == 422
    )
    assert (
        client.put(
            "/admin/v1/website/site", json={**body, "headline": "x" * 41}, headers=owner
        ).status_code
        == 422
    )
    assert "website.hero_update" in audit_actions(client, owner)


def test_image_upload_reuses_png_asset_storage(client):
    owner = make_admin(client)
    reply = client.post("/admin/v1/website/images", content=png(64), headers=owner)
    assert reply.status_code == 201
    url = reply.json()["url"]
    assert url.startswith("/api/v1/assets/") and url.endswith(".png")
    assert client.get(url.removeprefix("/api")).headers["content-type"] == "image/png"
    created = client.post("/admin/v1/website/news", json=post(image=url), headers=owner)
    assert created.status_code == 201
    not_png = client.post("/admin/v1/website/images", content=b"GIF89a....", headers=owner)
    assert not_png.status_code == 422
    assert "website.image_upload" in audit_actions(client, owner)


def test_releases_are_read_only_from_the_mounted_folder(client, tmp_path, monkeypatch):
    owner = make_admin(client)
    monkeypatch.delenv("RELEASES_DIR", raising=False)
    assert client.get("/admin/v1/website/releases", headers=owner).json()["configured"] is False
    monkeypatch.setenv("RELEASES_DIR", str(tmp_path))
    empty = client.get("/admin/v1/website/releases", headers=owner).json()
    assert empty == {"configured": True, "latest": None, "history": [], "files": []}
    release = {
        "version": "0.2.0-beta",
        "fileName": "bupbup-windows-0.2.0-beta.zip",
        "fileSizeBytes": 12,
        "sha256": "ab" * 32,
        "publishedAt": "2026-10-18T00:00:00+00:00",
        "notes": "Ghi chú",
        "secret": "not echoed",
    }
    (tmp_path / "latest.json").write_text(json.dumps(release))
    (tmp_path / "history.json").write_text(json.dumps([{**release, "version": "0.1.0"}, release]))
    (tmp_path / "bupbup-windows-0.2.0-beta.zip").write_bytes(b"PK\x03\x04zipdata")
    data = client.get("/admin/v1/website/releases", headers=owner).json()
    assert data["latest"]["version"] == "0.2.0-beta" and "secret" not in data["latest"]
    assert [r["version"] for r in data["history"]] == ["0.2.0-beta", "0.1.0"]
    assert data["files"][0]["name"] == "bupbup-windows-0.2.0-beta.zip"
    (tmp_path / "latest.json").write_text("{broken")
    assert client.get("/admin/v1/website/releases", headers=owner).json()["latest"] is None
