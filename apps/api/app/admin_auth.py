"""Admin portal identity: separate admin accounts, role permissions, TOTP and audit log.

Admin tokens use audience ``suni-admin`` so player tokens (``suni-arena``) never pass
here and admin tokens never open an arena seat.
"""

import base64
import hmac
import json
import secrets
import struct
import time
import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated, Literal
from urllib.parse import quote

import jwt
import redis
from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, Field
from sqlalchemy import Boolean, DateTime, Integer, String, Text, func, select
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.main import DUMMY_HASH, JWT_SECRET, Base, Db, limiter, password_hash

router = APIRouter(prefix="/admin/v1")
bearer = HTTPBearer(auto_error=False)
AUDIENCE = "suni-admin"
TOKEN_HOURS = 4
Role = Literal["owner", "operator", "viewer"]
# owner: everything incl. admin accounts; operator: live ops + sanctions; viewer: read only.
PERMISSIONS: dict[str, set[str]] = {
    "owner": {"read", "liveops", "sanction", "admins"},
    "operator": {"read", "liveops", "sanction"},
    "viewer": {"read"},
}


def now() -> datetime:
    return datetime.now(UTC)


class AdminUser(Base):
    __tablename__ = "admin_users"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    username: Mapped[str] = mapped_column(String(32), unique=True)
    password: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(16))
    totp_secret: Mapped[str | None] = mapped_column(String(64))
    totp_pending: Mapped[str | None] = mapped_column(String(64))
    disabled: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AuditLog(Base):
    __tablename__ = "admin_audit_logs"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    actor_admin_id: Mapped[str | None] = mapped_column(String(36))
    actor_name: Mapped[str] = mapped_column(String(32))
    action: Mapped[str] = mapped_column(String(64))
    target_type: Mapped[str] = mapped_column(String(32))
    target_id: Mapped[str] = mapped_column(String(64))
    reason: Mapped[str] = mapped_column(String(500), default="")
    detail: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def audit(
    db: Session,
    actor: AdminUser | None,
    action: str,
    target_type: str,
    target_id: str,
    reason: str = "",
    **detail,
) -> None:
    """Adds an audit row to the caller's transaction; never stores secrets."""
    db.add(
        AuditLog(
            actor_admin_id=actor.id if actor else None,
            actor_name=actor.username if actor else "system",
            action=action,
            target_type=target_type,
            target_id=str(target_id),
            reason=reason,
            detail=json.dumps(detail, default=str, ensure_ascii=False),
            created_at=now(),
        )
    )


def totp_code(secret: str, step: int) -> str:
    key = base64.b32decode(secret)
    digest = hmac.new(key, struct.pack(">Q", step), "sha1").digest()
    offset = digest[-1] & 0x0F
    value = struct.unpack(">I", digest[offset : offset + 4])[0] & 0x7FFFFFFF
    return f"{value % 1_000_000:06d}"


def totp_valid(secret: str, code: str | None) -> bool:
    if not code or len(code) != 6 or not code.isdigit():
        return False
    step = int(time.time()) // 30
    return any(hmac.compare_digest(totp_code(secret, step + d), code) for d in (-1, 0, 1))


def check_admin_rate(request: Request):
    # Own bucket so player logins cannot lock admins out, and the reverse.
    ip = request.client.host if request.client else "unknown"
    script = """
    local count = redis.call('INCR', KEYS[1])
    if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
    return count
    """
    try:
        attempts = limiter.eval(script, 1, f"admin-auth:{ip}", 300)
    except redis.RedisError as exc:
        raise HTTPException(503, "Admin login temporarily unavailable") from exc
    if attempts > 10:
        raise HTTPException(429, "Too many attempts", headers={"Retry-After": "300"})


def issue(admin: AdminUser) -> dict:
    issued = now()
    token = jwt.encode(
        {
            "sub": admin.id,
            "name": admin.username,
            "role": admin.role,
            "iss": "suni-api",
            "aud": AUDIENCE,
            "iat": issued,
            "exp": issued + timedelta(hours=TOKEN_HOURS),
        },
        JWT_SECRET,
        algorithm="HS256",
    )
    return {"access_token": token, "expires_in": TOKEN_HOURS * 3600, "admin": view(admin)}


def view(admin: AdminUser) -> dict:
    return {
        "id": admin.id,
        "username": admin.username,
        "role": admin.role,
        "mfa": admin.totp_secret is not None,
        "disabled": admin.disabled,
        "last_login_at": admin.last_login_at,
        "permissions": sorted(PERMISSIONS.get(admin.role, set())),
    }


def current_admin(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)], db: Db
) -> AdminUser:
    if credentials is None:
        raise HTTPException(401, "Admin sign-in required")
    try:
        claims = jwt.decode(
            credentials.credentials,
            JWT_SECRET,
            algorithms=["HS256"],
            audience=AUDIENCE,
            issuer="suni-api",
            options={"require": ["sub", "exp", "iat"]},
        )
    except jwt.InvalidTokenError as exc:
        raise HTTPException(401, "Invalid or expired admin token") from exc
    admin = db.get(AdminUser, claims["sub"])
    # Re-read every request: disabling or demoting an admin takes effect at once.
    if admin is None or admin.disabled:
        raise HTTPException(401, "Admin account disabled")
    return admin


Admin = Annotated[AdminUser, Depends(current_admin)]


def require(permission: str):
    def check(admin: Admin) -> AdminUser:
        if permission not in PERMISSIONS.get(admin.role, set()):
            raise HTTPException(403, "Your role cannot do this")
        return admin

    return check


Reader = Annotated[AdminUser, Depends(require("read"))]
Operator = Annotated[AdminUser, Depends(require("liveops"))]
Moderator = Annotated[AdminUser, Depends(require("sanction"))]
Owner = Annotated[AdminUser, Depends(require("admins"))]


class LoginBody(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=1, max_length=128)
    otp: str | None = Field(default=None, max_length=6)


@router.post("/auth/login", dependencies=[Depends(check_admin_rate)])
def login(body: LoginBody, db: Db):
    admin = db.scalar(select(AdminUser).where(AdminUser.username == body.username.lower()))
    valid = password_hash.verify(body.password, admin.password if admin else DUMMY_HASH)
    if not admin or not valid or admin.disabled:
        audit(db, None, "admin.login_failed", "admin", body.username.lower()[:64])
        db.commit()
        raise HTTPException(401, "Invalid credentials")
    if admin.totp_secret and not totp_valid(admin.totp_secret, body.otp):
        raise HTTPException(401, "MFA code required" if not body.otp else "Invalid MFA code")
    admin.last_login_at = now()
    audit(db, admin, "admin.login", "admin", admin.id)
    db.commit()
    return issue(admin)


@router.get("/auth/me")
def me(admin: Admin):
    return view(admin)


class PasswordBody(BaseModel):
    password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=12, max_length=128)


@router.post("/auth/password", status_code=204)
def change_password(body: PasswordBody, admin: Admin, db: Db):
    if not password_hash.verify(body.password, admin.password):
        raise HTTPException(401, "Current password is wrong")
    admin.password = password_hash.hash(body.new_password)
    audit(db, admin, "admin.password_changed", "admin", admin.id)
    db.commit()


@router.post("/auth/mfa/setup")
def mfa_setup(admin: Admin, db: Db):
    secret = base64.b32encode(secrets.token_bytes(20)).decode()
    admin.totp_pending = secret
    db.commit()
    label = quote(f"BupBup Admin:{admin.username}")
    return {"secret": secret, "uri": f"otpauth://totp/{label}?secret={secret}&issuer=BupBup"}


class CodeBody(BaseModel):
    otp: str = Field(min_length=6, max_length=6)


@router.post("/auth/mfa/enable")
def mfa_enable(body: CodeBody, admin: Admin, db: Db):
    if not admin.totp_pending or not totp_valid(admin.totp_pending, body.otp):
        raise HTTPException(400, "Invalid MFA code")
    admin.totp_secret = admin.totp_pending
    admin.totp_pending = None
    audit(db, admin, "admin.mfa_enabled", "admin", admin.id)
    db.commit()
    return view(admin)


class NewAdmin(BaseModel):
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-z0-9_.]+$")
    password: str = Field(min_length=12, max_length=128)
    role: Role


def create_admin(db: Session, username: str, password: str, role: str) -> AdminUser:
    admin = AdminUser(
        id=str(uuid.uuid4()),
        username=username.lower(),
        password=password_hash.hash(password),
        role=role,
        disabled=False,
        created_at=now(),
    )
    db.add(admin)
    return admin


@router.get("/admins")
def list_admins(_: Owner, db: Db):
    return {"admins": [view(a) for a in db.scalars(select(AdminUser).order_by(AdminUser.username))]}


@router.post("/admins", status_code=201)
def add_admin(body: NewAdmin, owner: Owner, db: Db):
    if db.scalar(select(AdminUser).where(AdminUser.username == body.username)):
        raise HTTPException(409, "Admin username taken")
    admin = create_admin(db, body.username, body.password, body.role)
    audit(db, owner, "admin.created", "admin", admin.id, role=body.role, username=body.username)
    db.commit()
    return view(admin)


class AdminPatch(BaseModel):
    role: Role | None = None
    disabled: bool | None = None
    reset_mfa: bool = False


@router.patch("/admins/{admin_id}")
def update_admin(admin_id: str, body: AdminPatch, owner: Owner, db: Db):
    admin = db.get(AdminUser, admin_id)
    if admin is None:
        raise HTTPException(404, "Admin not found")
    if admin.id == owner.id and (body.disabled or (body.role and body.role != "owner")):
        raise HTTPException(400, "You cannot demote or disable yourself")
    before = view(admin)
    if body.role:
        admin.role = body.role
    if body.disabled is not None:
        admin.disabled = body.disabled
    if body.reset_mfa:
        admin.totp_secret = None
        admin.totp_pending = None
    owners = db.scalar(
        select(func.count())
        .select_from(AdminUser)
        .where(AdminUser.role == "owner", AdminUser.disabled.is_(False))
    )
    if owners == 0:
        db.rollback()
        raise HTTPException(400, "Keep at least one active owner")
    audit(db, owner, "admin.updated", "admin", admin.id, before=before, after=view(admin))
    db.commit()
    return view(admin)


@router.get("/audit")
def audit_log(
    _: Reader,
    db: Db,
    limit: int = 100,
    action: str | None = None,
    target_id: str | None = None,
):
    query = select(AuditLog).order_by(AuditLog.id.desc()).limit(min(max(limit, 1), 500))
    if action:
        query = query.where(AuditLog.action.like(action.replace("%", "") + "%"))
    if target_id:
        query = query.where(AuditLog.target_id == target_id)
    return {
        "entries": [
            {
                "id": row.id,
                "actor": row.actor_name,
                "action": row.action,
                "target_type": row.target_type,
                "target_id": row.target_id,
                "reason": row.reason,
                "detail": json.loads(row.detail or "{}"),
                "created_at": row.created_at,
            }
            for row in db.scalars(query)
        ]
    }
