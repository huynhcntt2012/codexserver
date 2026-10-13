import os
import uuid
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from typing import Annotated

import jwt
import redis
from fastapi import Depends, FastAPI, HTTPException, Request
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
    vip_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


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
        return account
    except jwt.InvalidTokenError as exc:
        raise HTTPException(401, "Invalid or expired access token") from exc


Identity = Annotated[Account, Depends(current_account)]


class Credentials(BaseModel):
    username: str = Field(min_length=3, max_length=24, pattern=r"^[a-z0-9_]+$")
    password: str = Field(min_length=10, max_length=128)


def create_account(db: Session, username: str | None = None, password: str | None = None):
    account = Account(
        id=str(uuid.uuid4()),
        username=username,
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
def register(body: Credentials, db: Db):
    try:
        account = create_account(db, body.username, body.password)
    except IntegrityError as exc:
        db.rollback()
        raise HTTPException(409, "Username unavailable") from exc
    return issue_token(account)


@app.post("/v1/login", dependencies=[Depends(check_rate)])
def login(body: Credentials, db: Db):
    account = db.scalar(select(Account).where(Account.username == body.username))
    valid = password_hash.verify(body.password, account.password if account else DUMMY_HASH)
    if not account or not valid:
        raise HTTPException(401, "Invalid credentials")
    return issue_token(account)


@app.get("/v1/me")
def me(account: Identity):
    return {"id": account.id, "name": account.display_name, "guest": account.username is None}


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
