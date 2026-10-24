import os
import re
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import Annotated

import jwt
import redis
from fastapi import Depends, FastAPI, HTTPException, Request, Response
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pwdlib import PasswordHash
from pydantic import BaseModel, Field
from sqlalchemy import DateTime, ForeignKey, String, create_engine, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

JWT_SECRET = os.environ.get("JWT_SECRET", "")
if len(JWT_SECRET) < 32:
    raise RuntimeError("JWT_SECRET must contain at least 32 characters")
engine = create_engine(os.environ["DATABASE_URL"], pool_pre_ping=True)
SessionLocal = sessionmaker(engine)
limiter = redis.Redis.from_url(os.environ["REDIS_URL"], socket_timeout=2)
password_hash = PasswordHash.recommended()
# Equalize missing-user and wrong-password login work.
DUMMY_HASH = password_hash.hash("not-an-account-password")
bearer = HTTPBearer()


class Base(DeclarativeBase):
    pass


class Account(Base):
    __tablename__ = "accounts"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    username: Mapped[str | None] = mapped_column(String(24), unique=True)
    display_name: Mapped[str] = mapped_column(String(24))
    password: Mapped[str | None] = mapped_column(String(255))
    # Lowercased; only used to send password reset codes, never returned by the API.
    email: Mapped[str | None] = mapped_column(String(254), unique=True)
    vip_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    last_login_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Presence: refreshed (at most every 30 s) by any signed-in API call.
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


ONLINE_WINDOW = timedelta(minutes=2)


class AccountSanction(Base):
    """Admin ban. Active while not revoked and not past expires_at (null = permanent)."""

    __tablename__ = "account_sanctions"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(16), default="ban")
    reason: Mapped[str] = mapped_column(String(500))
    created_by: Mapped[str] = mapped_column(String(32))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


def active_ban(db: Session, account_id: str) -> AccountSanction | None:
    now = datetime.now(UTC)
    for row in db.scalars(
        select(AccountSanction).where(
            AccountSanction.account_id == account_id, AccountSanction.revoked_at.is_(None)
        )
    ):
        expires = row.expires_at
        if expires and expires.tzinfo is None:
            expires = expires.replace(tzinfo=UTC)
        if expires is None or expires > now:
            return row
    return None


class InventoryItem(Base):
    __tablename__ = "inventory"
    account_id: Mapped[str] = mapped_column(ForeignKey("accounts.id"), primary_key=True)
    item_id: Mapped[str] = mapped_column(String(64), primary_key=True)


@asynccontextmanager
async def lifespan(_app: FastAPI):
    yield
    engine.dispose()
    limiter.close()


app = FastAPI(title="Suni Bomb Arena API", version="0.1.0", lifespan=lifespan)


def db_session():
    with SessionLocal() as session:
        yield session


Db = Annotated[Session, Depends(db_session)]


def check_rate(request: Request):
    # Atomic fixed window. Never trusts arbitrary X-Forwarded-For headers.
    ip = request.client.host if request.client else "unknown"
    script = """
    local count = redis.call('INCR', KEYS[1])
    if count == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
    return count
    """
    try:
        attempts = limiter.eval(script, 1, f"auth:{ip}", 60)
    except redis.RedisError as exc:
        raise HTTPException(503, "Authentication temporarily unavailable") from exc
    if attempts > 20:
        raise HTTPException(429, "Too many requests", headers={"Retry-After": "60"})


def issue_token(account: Account):
    now = datetime.now(UTC)
    token = jwt.encode(
        {
            "sub": account.id,
            "name": account.display_name,
            "iss": "suni-api",
            "aud": "suni-arena",
            "iat": now,
            "exp": now + timedelta(hours=1),
        },
        JWT_SECRET,
        algorithm="HS256",
    )
    return {
        "access_token": token,
        "token_type": "bearer",
        "expires_in": 3600,
        "account_id": account.id,
        "name": account.display_name,
    }


def current_account(credentials: Annotated[HTTPAuthorizationCredentials, Depends(bearer)], db: Db):
    try:
        claims = jwt.decode(
            credentials.credentials,
            JWT_SECRET,
            algorithms=["HS256"],
            audience="suni-arena",
            issuer="suni-api",
            options={"require": ["sub", "exp", "iat"]},
        )
        account = db.get(Account, claims["sub"])
        if account is None:
            raise HTTPException(401, "Account not found")
        # Existing tokens stop working for the API at once; arena seats are not re-checked.
        if active_ban(db, account.id):
            raise HTTPException(403, "Account suspended")
        seen = account.last_seen_at
        if seen and seen.tzinfo is None:
            seen = seen.replace(tzinfo=UTC)
        current = datetime.now(UTC)
        if seen is None or current - seen > timedelta(seconds=30):
            account.last_seen_at = current
            db.commit()
        return account
    except jwt.InvalidTokenError as exc:
        raise HTTPException(401, "Invalid or expired access token") from exc


Identity = Annotated[Account, Depends(current_account)]


class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=24, pattern=r"^[a-z0-9_]+$")
    password: str = Field(min_length=10, max_length=128)


EMAIL = r"^[^@\s]{1,64}@[^@\s]+\.[^@\s]{2,}$"


class Registration(Credentials):
    email: str | None = Field(default=None, max_length=254, pattern=EMAIL)


def create_account(
    db: Session,
    username: str | None = None,
    password: str | None = None,
    email: str | None = None,
):
    account = Account(
        id=str(uuid.uuid4()),
        username=username,
        email=email.lower() if email else None,
        created_at=datetime.now(UTC),
        last_login_at=datetime.now(UTC),
        display_name=username or f"Suni-{uuid.uuid4().hex[:6]}",
        password=password_hash.hash(password) if password else None,
    )
    db.add(account)
    db.flush()
    db.add(InventoryItem(account_id=account.id, item_id="pilot_default"))
    db.commit()
    return account


@app.get("/health")
def health(db: Db):
    try:
        db.execute(text("SELECT 1"))
        limiter.ping()
    except Exception as exc:
        raise HTTPException(503, "Dependency unavailable") from exc
    return {"status": "ok"}


@app.post("/v1/guests", status_code=201, dependencies=[Depends(check_rate)])
def guest(db: Db):
    return issue_token(create_account(db))


@app.post("/v1/register", status_code=201, dependencies=[Depends(check_rate)])
def register(body: Registration, db: Db):
    try:
        account = create_account(db, body.username, body.password, body.email)
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Username or email unavailable") from exc
    return issue_token(account)


@app.post("/v1/login", dependencies=[Depends(check_rate)])
def login(body: Credentials, db: Db):
    account = db.scalar(select(Account).where(Account.username == body.username))
    valid = password_hash.verify(body.password, account.password if account else DUMMY_HASH)
    if not account or not valid:
        raise HTTPException(401, "Invalid credentials")
    if active_ban(db, account.id):
        raise HTTPException(403, "Account suspended")
    account.last_login_at = datetime.now(UTC)
    account.last_seen_at = account.last_login_at
    db.commit()
    return issue_token(account)


class PasswordChange(Credentials):
    new_password: str = Field(min_length=10, max_length=128)


@app.post("/v1/password", status_code=204, dependencies=[Depends(check_rate)])
def change_password(body: PasswordChange, db: Db):
    """Changes a password from the login screen; the current password proves ownership."""
    account = db.scalar(select(Account).where(Account.username == body.username))
    valid = password_hash.verify(body.password, account.password if account else DUMMY_HASH)
    if not account or not valid:
        raise HTTPException(401, "Invalid credentials")
    if body.new_password == body.password:
        raise HTTPException(422, "New password must differ from the current one")
    account.password = password_hash.hash(body.new_password)
    db.commit()
    return Response(status_code=204)


def masked_email(address: str | None) -> str | None:
    """b***@gmail.com: enough for the owner to recognise, never the full address."""
    if not address or "@" not in address:
        return None
    local, domain = address.split("@", 1)
    return f"{local[:1]}***@{domain}"


@app.get("/v1/me")
def me(account: Identity):
    return {
        "id": account.id,
        "name": account.display_name,
        "guest": account.username is None,
        "username": account.username,
        "email": masked_email(account.email),
    }


class OwnPassword(BaseModel):
    password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=10, max_length=128)


class OwnEmail(BaseModel):
    password: str = Field(min_length=1, max_length=128)
    email: str = Field(max_length=254, pattern=EMAIL)


def check_own_password(account: Account, password: str) -> None:
    """Signed-in changes still need the current password (a stolen token is not enough)."""
    if account.username is None or not account.password:
        raise HTTPException(403, "Guest accounts have no password")
    if not password_hash.verify(password, account.password):
        raise HTTPException(401, "Invalid credentials")


@app.post("/v1/me/password", status_code=204, dependencies=[Depends(check_rate)])
def change_own_password(body: OwnPassword, account: Identity, db: Db):
    """Settings window: change the password of the signed-in account."""
    check_own_password(account, body.password)
    if body.new_password == body.password:
        raise HTTPException(422, "New password must differ from the current one")
    account.password = password_hash.hash(body.new_password)
    db.commit()
    return Response(status_code=204)


@app.put("/v1/me/email", dependencies=[Depends(check_rate)])
def change_own_email(body: OwnEmail, account: Identity, db: Db):
    """Sets the address password-reset codes go to (not verified by a code yet)."""
    check_own_password(account, body.password)
    account.email = body.email.strip().lower()
    try:
        db.commit()
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Email unavailable") from exc
    return {"email": masked_email(account.email)}


DISPLAY_NAME = re.compile(r"^[\w .\-]{2,24}$")


class ProfilePatch(BaseModel):
    display_name: str = Field(min_length=2, max_length=24)


@app.patch("/v1/me")
def rename(body: ProfilePatch, account: Identity, db: Db):
    """Players choose their display name; the login name never changes."""
    name = " ".join(body.display_name.split())
    if not DISPLAY_NAME.match(name):
        raise HTTPException(422, "2-24 letters, digits, spaces, . _ -")
    account.display_name = name
    db.commit()
    return {"id": account.id, "name": account.display_name}


@app.get("/v1/inventory")
def inventory(account: Identity, db: Db):
    return {
        "items": list(
            db.scalars(select(InventoryItem.item_id).where(InventoryItem.account_id == account.id))
        )
    }


@app.get("/v1/vip")
def vip(account: Identity):
    until = account.vip_until
    if until and until.tzinfo is None:
        until = until.replace(tzinfo=UTC)
    return {"active": bool(until and until > datetime.now(UTC)), "expires_at": until}


# Imported last: the social routes reuse the models and dependencies above.
from app.admin_api import player_router  # noqa: E402
from app.admin_api import router as admin_router  # noqa: E402
from app.admin_auth import router as admin_auth_router  # noqa: E402
from app.battle_items import router as battle_items_router  # noqa: E402
from app.boss import router as boss_router  # noqa: E402
from app.economy import router as economy_router  # noqa: E402
from app.invites import router as invites_router  # noqa: E402
from app.leaderboard import router as leaderboard_router  # noqa: E402
from app.liveops import router as liveops_router  # noqa: E402
from app.mail import router as mail_router  # noqa: E402
from app.maps import router as maps_router  # noqa: E402
from app.matches import router as matches_router  # noqa: E402
from app.portal import router as portal_router  # noqa: E402
from app.progression import router as progression_router  # noqa: E402
from app.recovery import router as recovery_router  # noqa: E402
from app.social import router as social_router  # noqa: E402
from app.website import router as website_router  # noqa: E402

app.include_router(social_router)
app.include_router(recovery_router)
app.include_router(admin_auth_router)
app.include_router(admin_router)
app.include_router(player_router)
app.include_router(economy_router)
app.include_router(matches_router)
app.include_router(maps_router)
app.include_router(liveops_router)
app.include_router(invites_router)
app.include_router(battle_items_router)
app.include_router(portal_router)
app.include_router(website_router)
app.include_router(boss_router)
app.include_router(leaderboard_router)
app.include_router(mail_router)
app.include_router(progression_router)
