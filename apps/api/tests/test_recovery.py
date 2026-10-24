import pytest

from app import recovery


@pytest.fixture
def outbox(monkeypatch):
    sent = []
    monkeypatch.setenv("MAIL_MODE", "smtp")
    monkeypatch.setattr(recovery, "deliver", lambda address, code: sent.append((address, code)))
    return sent


def register(client, email="Pilot@Gmail.com"):
    body = {"username": "mail_pilot", "password": "first-password-1", "email": email}
    assert client.post("/v1/register", json=body).status_code == 201


def test_register_email_is_optional_unique_and_validated(client):
    register(client)
    other = {"username": "other_pilot", "password": "first-password-1", "email": "pilot@gmail.com"}
    assert client.post("/v1/register", json=other).status_code == 409
    bad = {**other, "email": "not-an-email"}
    assert client.post("/v1/register", json=bad).status_code == 422
    plain = {"username": "plain_pilot", "password": "first-password-1"}
    assert client.post("/v1/register", json=plain).status_code == 201


def test_forgot_sends_code_and_reset_changes_password(client, outbox):
    register(client)
    assert client.post("/v1/password/forgot", json={"email": "PILOT@gmail.com"}).status_code == 202
    assert len(outbox) == 1 and outbox[0][0] == "pilot@gmail.com"
    code = outbox[0][1]
    assert len(code) == 6 and code.isdigit()
    # Asking again within a minute keeps the same code and sends nothing.
    client.post("/v1/password/forgot", json={"email": "pilot@gmail.com"})
    assert len(outbox) == 1
    reset = {"email": "pilot@gmail.com", "code": code, "new_password": "second-password-2"}
    wrong = {**reset, "code": "000000" if code != "000000" else "111111"}
    assert client.post("/v1/password/reset", json=wrong).status_code == 400
    assert client.post("/v1/password/reset", json={**reset, "code": "12a456"}).status_code == 422
    assert client.post("/v1/password/reset", json=reset).status_code == 204
    assert client.post("/v1/password/reset", json=reset).status_code == 400
    login = {"username": "mail_pilot", "password": "second-password-2"}
    assert client.post("/v1/login", json=login).status_code == 200


def test_unknown_email_looks_the_same_and_sends_nothing(client, outbox):
    assert client.post("/v1/password/forgot", json={"email": "who@gmail.com"}).json() == {
        "status": "sent"
    }
    assert outbox == []
    reset = {"email": "who@gmail.com", "code": "123456", "new_password": "second-password-2"}
    assert client.post("/v1/password/reset", json=reset).status_code == 400


def test_too_many_wrong_codes_burn_the_code(client, outbox):
    register(client)
    client.post("/v1/password/forgot", json={"email": "pilot@gmail.com"})
    code = outbox[0][1]
    wrong = "000000" if code != "000000" else "111111"
    body = {"email": "pilot@gmail.com", "new_password": "second-password-2"}
    for _ in range(recovery.MAX_ATTEMPTS):
        client.post("/v1/password/reset", json={**body, "code": wrong})
    assert client.post("/v1/password/reset", json={**body, "code": code}).status_code == 400


def test_mail_disabled_or_failing_is_reported(client, monkeypatch):
    register(client)
    monkeypatch.setenv("MAIL_MODE", "disabled")
    assert client.post("/v1/password/forgot", json={"email": "pilot@gmail.com"}).status_code == 503
    monkeypatch.setenv("MAIL_MODE", "smtp")
    monkeypatch.delenv("SMTP_HOST", raising=False)
    assert client.post("/v1/password/forgot", json={"email": "pilot@gmail.com"}).status_code == 503
    # The failed send leaves no code behind, so a retry can send immediately.
    monkeypatch.setattr(recovery, "deliver", lambda address, code: None)
    assert client.post("/v1/password/forgot", json={"email": "pilot@gmail.com"}).status_code == 202
