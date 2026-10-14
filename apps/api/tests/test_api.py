import os

os.environ.setdefault("JWT_SECRET", "test-only-key-32-characters-long-do-not-deploy")
os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/15")

import jwt  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from app import main  # noqa: E402


@pytest.fixture
def client():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    main.Base.metadata.create_all(engine)

    def database():
        with Session(engine) as db:
            yield db

    main.app.dependency_overrides[main.db_session] = database
    main.app.dependency_overrides[main.check_rate] = lambda: None
    with TestClient(main.app) as test_client:
        yield test_client
    main.app.dependency_overrides.clear()
    engine.dispose()


def test_guest_identity_inventory_and_no_vip(client):
    response = client.post("/v1/guests")
    assert response.status_code == 201
    headers = {"Authorization": "Bearer " + response.json()["access_token"]}
    assert client.get("/v1/me", headers=headers).json()["guest"] is True
    assert client.get("/v1/inventory", headers=headers).json() == {"items": ["pilot_default"]}
    assert client.get("/v1/vip", headers=headers).json() == {"active": False, "expires_at": None}
    assert client.post("/v1/vip", headers=headers, json={"active": True}).status_code == 405


def test_registration_login_duplicate_and_invalid_password(client):
    body = {"username": "test_pilot", "password": "long-enough-password"}
    registered = client.post("/v1/register", json=body)
    assert registered.status_code == 201
    account_id = registered.json()["account_id"]
    for db in main.app.dependency_overrides[main.db_session]():
        account = db.get(main.Account, account_id)
        assert account.password != body["password"]
        assert account.password.startswith("$argon2id$")
        assert main.password_hash.verify(body["password"], account.password)
    assert client.post("/v1/register", json=body).status_code == 409
    logged_in = client.post("/v1/login", json=body)
    assert logged_in.status_code == 200
    assert logged_in.json()["account_id"] == account_id
    headers = {"Authorization": "Bearer " + logged_in.json()["access_token"]}
    assert client.get("/v1/me", headers=headers).json() == {
        "id": account_id,
        "name": body["username"],
        "guest": False,
    }
    assert client.get("/v1/inventory", headers=headers).json() == {"items": ["pilot_default"]}
    assert "password" not in logged_in.json()
    body["password"] = "wrong-password"
    assert client.post("/v1/login", json=body).status_code == 401
    body["username"] = "missing_pilot"
    assert client.post("/v1/login", json=body).status_code == 401


def test_rejects_weak_password_and_invalid_name(client):
    assert (
        client.post("/v1/register", json={"username": "x", "password": "short"}).status_code == 422
    )


@pytest.mark.parametrize(
    "username,password",
    [
        ("ab", "long-password"),
        ("a" * 25, "long-password"),
        ("Uppercase", "long-password"),
        ("pilot name", "long-password"),
        ("pilot!", "long-password"),
        ("pilot", "x" * 9),
        ("pilot", "x" * 129),
    ],
)
@pytest.mark.parametrize("path", ["/v1/register", "/v1/login"])
def test_credential_validation(client, path, username, password):
    assert client.post(path, json={"username": username, "password": password}).status_code == 422


@pytest.mark.parametrize("length", [10, 128])
def test_password_boundaries_and_exact_password(client, length):
    body = {"username": "a_1", "password": " " + "x" * (length - 2) + " "}
    assert client.post("/v1/register", json=body).status_code == 201
    assert client.post("/v1/login", json=body).status_code == 200
    assert client.post("/v1/login", json={**body, "password": "z" * length}).status_code == 401


def test_rejects_forged_expired_wrong_audience_tokens(client):
    assert client.get("/v1/me").status_code in (401, 403)
    for claims in [
        {"sub": "x", "exp": 1, "iat": 0, "iss": "suni-api", "aud": "suni-arena"},
        {"sub": "x", "exp": 9999999999, "iat": 0, "iss": "suni-api", "aud": "other"},
        {"sub": "x", "iat": 0, "iss": "suni-api", "aud": "suni-arena"},
    ]:
        token = jwt.encode(claims, main.JWT_SECRET, algorithm="HS256")
        assert client.get("/v1/me", headers={"Authorization": "Bearer " + token}).status_code == 401
    assert client.get("/v1/me", headers={"Authorization": "Bearer forged"}).status_code == 401


def test_limiter_rejects_over_limit_and_fails_closed(client, monkeypatch):
    main.app.dependency_overrides.pop(main.check_rate)
    monkeypatch.setattr(main.limiter, "eval", lambda *args: 21)
    assert client.post("/v1/guests").status_code == 429

    def unavailable(*args):
        raise main.redis.ConnectionError()

    monkeypatch.setattr(main.limiter, "eval", unavailable)
    assert client.post("/v1/guests").status_code == 503
