"""Forgotten-password reset: a six-digit code sent to the account's email address."""

import hmac
import logging
import os
import secrets
import smtplib
from datetime import UTC, datetime, timedelta
from email.message import EmailMessage

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel, Field
from sqlalchemy import DateTime, ForeignKey, Integer, String, select
from sqlalchemy.orm import Mapped, mapped_column

from app.main import EMAIL, JWT_SECRET, Account, Base, Db, check_rate, password_hash

router = APIRouter(prefix="/v1/password")
log = logging.getLogger("suni.recovery")
CODE_TTL = timedelta(minutes=15)
RESEND_AFTER = timedelta(seconds=60)
MAX_ATTEMPTS = 5


class PasswordReset(Base):
    __tablename__ = "password_resets"
    account_id: Mapped[str] = mapped_column(
        ForeignKey("accounts.id", ondelete="CASCADE"), primary_key=True
    )
    code_hash: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(Integer, default=0)


def mail_mode() -> str:
    # smtp: send for real; log: print the code in the API log (local testing only).
    return os.environ.get("MAIL_MODE", "disabled")


def digest(code: str) -> str:
    return hmac.new(JWT_SECRET.encode(), code.encode(), "sha256").hexdigest()


def aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def deliver(address: str, code: str) -> None:
    if mail_mode() == "log":
        log.warning("Password reset code for %s: %s", address, code)
        return
    message = EmailMessage()
    message["From"] = os.environ.get("MAIL_FROM") or os.environ["SMTP_USER"]
    message["To"] = address
    message["Subject"] = "Mã đặt lại mật khẩu Bụp Bụp"
    message.set_content(
        f"Mã đặt lại mật khẩu của bạn là {code}.\n"
        "Mã có hiệu lực 15 phút. Nếu bạn không yêu cầu, hãy bỏ qua email này."
    )
    port = int(os.environ.get("SMTP_PORT", "587"))
    with smtplib.SMTP(os.environ["SMTP_HOST"], port, timeout=10) as smtp:
        smtp.starttls()
        smtp.login(os.environ["SMTP_USER"], os.environ["SMTP_PASSWORD"])
        smtp.send_message(message)


class Forgot(BaseModel):
    email: str = Field(max_length=254, pattern=EMAIL)


class Reset(Forgot):
    code: str = Field(pattern=r"^[0-9]{6}$")
    new_password: str = Field(min_length=10, max_length=128)


def by_email(db, address: str) -> Account | None:
    return db.scalar(select(Account).where(Account.email == address.lower()))


@router.post("/forgot", status_code=202, dependencies=[Depends(check_rate)])
def forgot(body: Forgot, db: Db):
    """Same answer whether or not the address has an account, so emails cannot be probed."""
    if mail_mode() not in ("smtp", "log"):
        raise HTTPException(503, "Email delivery is not configured")
    account = by_email(db, body.email)
    if account is None:
        return {"status": "sent"}
    now = datetime.now(UTC)
    row = db.get(PasswordReset, account.id)
    if row is not None and now - aware(row.created_at) < RESEND_AFTER:
        return {"status": "sent"}
    code = f"{secrets.randbelow(1_000_000):06d}"
    if row is None:
        row = PasswordReset(account_id=account.id)
        db.add(row)
    row.code_hash = digest(code)
    row.created_at = now
    row.expires_at = now + CODE_TTL
    row.attempts = 0
    db.commit()
    try:
        deliver(account.email, code)
    except (OSError, KeyError, smtplib.SMTPException) as exc:
        db.delete(row)
        db.commit()
        raise HTTPException(503, "Could not send email") from exc
    return {"status": "sent"}


@router.post("/reset", status_code=204, dependencies=[Depends(check_rate)])
def reset(body: Reset, db: Db):
    account = by_email(db, body.email)
    row = db.get(PasswordReset, account.id) if account else None
    if row is None or aware(row.expires_at) < datetime.now(UTC) or row.attempts >= MAX_ATTEMPTS:
        raise HTTPException(400, "Code invalid or expired")
    if not hmac.compare_digest(row.code_hash, digest(body.code)):
        row.attempts += 1
        db.commit()
        raise HTTPException(400, "Code invalid or expired")
    account.password = password_hash.hash(body.new_password)
    db.delete(row)
    db.commit()
    return Response(status_code=204)
