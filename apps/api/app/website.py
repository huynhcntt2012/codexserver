"""Website CMS for the promotion site at / (docs/PORTAL.md).

Admins edit news posts and the home hero text in the Admin Portal ("Website"); the
site reads them through public, read-only endpoints. Everything is plain text: the
site only ever assigns it with textContent, and here control characters are dropped
and images are limited to the site's own art or content-addressed uploads.

Downloads stay with scripts/publish-release.py; admins only see latest.json and the
release history it writes (RELEASES_DIR, mounted read-only).
"""

import json
import os
import re
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

from fastapi import APIRouter, HTTPException, Query, Request, Response
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import JSON, Boolean, DateTime, String, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, Session, mapped_column

from app.admin_auth import Operator, Reader, audit
from app.economy import MAX_ICON_BYTES, store_asset
from app.main import Base, Db

router = APIRouter()

CACHE = "public, max-age=60"
Category = Literal["Cập nhật", "Sự kiện", "Hướng dẫn"]
SLUG = r"^[a-z0-9]+(?:-[a-z0-9]+)*$"
# Site art shipped with the web image, or a PNG uploaded through this module.
IMAGE = r"^(/img/[a-z0-9-]+\.webp|/api/v1/assets/[0-9a-f]{64}\.png)$"
CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f​-‏ -‮⁦-⁩]")
MAX_RELEASE_FILE = 256 * 1024

# What the site shows when nobody has edited the hero yet (matches index.html).
HERO_DEFAULTS = {
    "headline": "Đặt bom nước",
    "headline_accent": "Đấu trí cùng bạn bè!",
    "subline": "Trận đấu vui nhộn · 5 nhân vật · 15 bản đồ",
    "cta_download": "Tải game ngay",
    "cta_demo": "Chơi demo",
}


def now() -> datetime:
    return datetime.now(UTC)


def aware(value: datetime) -> datetime:
    return value if value.tzinfo else value.replace(tzinfo=UTC)


def utc(value: datetime) -> datetime:
    return aware(value).astimezone(UTC)


def clean(value: str) -> str:
    """One line of plain text: no control/bidi characters, single spaces."""
    return " ".join(CONTROL.sub("", value).split())


class SiteNews(Base):
    __tablename__ = "site_news"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    slug: Mapped[str] = mapped_column(String(80), unique=True)
    title: Mapped[str] = mapped_column(String(120))
    category: Mapped[str] = mapped_column(String(16))
    excerpt: Mapped[str] = mapped_column(String(300), default="")
    body: Mapped[list] = mapped_column(JSON)
    image: Mapped[str] = mapped_column(String(120))
    pinned: Mapped[bool] = mapped_column(Boolean, default=False)
    status: Mapped[str] = mapped_column(String(12), default="draft")
    publish_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    created_by: Mapped[str] = mapped_column(String(32), default="system")
    updated_by: Mapped[str] = mapped_column(String(32), default="system")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class SiteSetting(Base):
    __tablename__ = "site_settings"
    key: Mapped[str] = mapped_column(String(32), primary_key=True)
    value: Mapped[dict] = mapped_column(JSON)
    updated_by: Mapped[str] = mapped_column(String(32), default="system")
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


def news_phase(post: SiteNews) -> str:
    if post.status != "published":
        return "draft"
    return "scheduled" if aware(post.publish_at) > now() else "published"


def news_view(post: SiteNews) -> dict:
    return {
        "id": post.id,
        "slug": post.slug,
        "title": post.title,
        "category": post.category,
        "excerpt": post.excerpt,
        "body": list(post.body or []),
        "image": post.image,
        "pinned": post.pinned,
        "status": post.status,
        "phase": news_phase(post),
        "publish_at": aware(post.publish_at),
        "created_by": post.created_by,
        "updated_by": post.updated_by,
        "updated_at": post.updated_at,
    }


def public_view(post: SiteNews, full: bool = False) -> dict:
    view = {
        "slug": post.slug,
        "title": post.title,
        "category": post.category,
        "excerpt": post.excerpt,
        "image": post.image,
        "pinned": post.pinned,
        "date": aware(post.publish_at).isoformat(),
    }
    if full:
        view["body"] = list(post.body or [])
    return view


class NewsFields(BaseModel):
    slug: str = Field(min_length=3, max_length=80, pattern=SLUG)
    title: str = Field(min_length=3, max_length=120)
    category: Category
    excerpt: str = Field(default="", max_length=300)
    body: list[str] = Field(min_length=1, max_length=40)
    image: str = Field(max_length=120, pattern=IMAGE)
    pinned: bool = False
    publish_at: datetime

    @field_validator("excerpt")
    @classmethod
    def one_line(cls, value: str) -> str:
        return clean(value)

    @field_validator("body")
    @classmethod
    def paragraphs(cls, value: list[str]) -> list[str]:
        cleaned = [clean(p) for p in value]
        cleaned = [p for p in cleaned if p]
        if not cleaned:
            raise ValueError("body needs at least one paragraph")
        if any(len(p) > 2000 for p in cleaned):
            raise ValueError("paragraphs are at most 2000 characters")
        return cleaned

    @field_validator("title")
    @classmethod
    def title_left(cls, value: str) -> str:
        value = clean(value)
        if len(value) < 3:
            raise ValueError("title needs at least 3 characters")
        return value


class HeroFields(BaseModel):
    headline: str = Field(min_length=2, max_length=40)
    headline_accent: str = Field(default="", max_length=60)
    subline: str = Field(default="", max_length=120)
    cta_download: str = Field(min_length=2, max_length=24)
    cta_demo: str = Field(min_length=2, max_length=24)

    @field_validator("*")
    @classmethod
    def one_line(cls, value: str) -> str:
        return clean(value)

    @field_validator("headline", "cta_download", "cta_demo")
    @classmethod
    def not_blank(cls, value: str) -> str:
        if len(value) < 2:
            raise ValueError("at least 2 visible characters")
        return value


def hero(db: Session) -> tuple[dict, SiteSetting | None]:
    row = db.get(SiteSetting, "hero")
    stored = row.value if row and isinstance(row.value, dict) else {}
    return {k: str(stored.get(k, v)) for k, v in HERO_DEFAULTS.items()}, row


def get_post(db: Session, post_id: str) -> SiteNews:
    post = db.get(SiteNews, post_id)
    if post is None:
        raise HTTPException(404, "Post not found")
    return post


def slug_taken(db: Session, slug: str, post_id: str | None = None) -> None:
    other = db.scalar(select(SiteNews).where(SiteNews.slug == slug))
    if other is not None and other.id != post_id:
        raise HTTPException(409, "Slug already exists")


def commit(db: Session) -> None:
    try:
        db.commit()
    except IntegrityError as exc:  # two admins saving the same slug at once
        db.rollback()
        raise HTTPException(409, "Slug already exists") from exc


# ---------------------------------------------------------------- Admin: news


@router.get("/admin/v1/website/news")
def admin_news(_: Reader, db: Db):
    rows = db.scalars(select(SiteNews).order_by(SiteNews.publish_at.desc()))
    return {"news": [news_view(p) for p in rows]}


@router.post("/admin/v1/website/news", status_code=201)
def create_news(body: NewsFields, admin: Operator, db: Db):
    slug_taken(db, body.slug)
    at = now()
    post = SiteNews(
        id=str(uuid.uuid4()),
        **body.model_dump(exclude={"publish_at"}),
        publish_at=utc(body.publish_at),
        status="draft",
        created_by=admin.username,
        updated_by=admin.username,
        created_at=at,
        updated_at=at,
    )
    db.add(post)
    audit(db, admin, "website.news_create", "news", post.id, slug=post.slug, title=post.title)
    commit(db)
    return news_view(post)


@router.put("/admin/v1/website/news/{post_id}")
def update_news(post_id: str, body: NewsFields, admin: Operator, db: Db):
    post = get_post(db, post_id)
    slug_taken(db, body.slug, post.id)
    before = news_view(post)
    for key, value in body.model_dump(exclude={"publish_at"}).items():
        setattr(post, key, value)
    post.publish_at = utc(body.publish_at)
    post.updated_by = admin.username
    post.updated_at = now()
    audit(db, admin, "website.news_update", "news", post.id, before=before, after=news_view(post))
    commit(db)
    return news_view(post)


@router.post("/admin/v1/website/news/{post_id}/{action}")
def news_status(post_id: str, action: Literal["publish", "unpublish"], admin: Operator, db: Db):
    post = get_post(db, post_id)
    post.status = "published" if action == "publish" else "draft"
    post.updated_by = admin.username
    post.updated_at = now()
    audit(db, admin, f"website.news_{action}", "news", post.id, slug=post.slug)
    db.commit()
    return news_view(post)


@router.delete("/admin/v1/website/news/{post_id}")
def delete_news(post_id: str, admin: Operator, db: Db):
    post = get_post(db, post_id)
    audit(db, admin, "website.news_delete", "news", post.id, before=news_view(post))
    db.delete(post)
    db.commit()
    return {"deleted": post_id}


@router.post("/admin/v1/website/images", status_code=201)
async def upload_image(request: Request, admin: Operator, db: Db):
    """Raw PNG body (<= 10 MB, same checks and storage as item icons)."""
    length = request.headers.get("content-length")
    if length and int(length) > MAX_ICON_BYTES:
        raise HTTPException(413, "Icon larger than 10 MB")
    asset = store_asset(db, await request.body())
    audit(db, admin, "website.image_upload", "asset", asset.sha256, size=asset.size)
    db.commit()
    return {
        "url": f"/api/v1/assets/{asset.sha256}.png",
        "width": asset.width,
        "height": asset.height,
    }


# ---------------------------------------------------------------- Admin: hero


@router.get("/admin/v1/website/site")
def admin_site(_: Reader, db: Db):
    values, row = hero(db)
    return {
        "hero": values,
        "defaults": HERO_DEFAULTS,
        "updated_by": row.updated_by if row else None,
        "updated_at": row.updated_at if row else None,
    }


@router.put("/admin/v1/website/site")
def update_site(body: HeroFields, admin: Operator, db: Db):
    before, row = hero(db)
    if row is None:
        row = SiteSetting(key="hero", value={}, updated_at=now())
        db.add(row)
    row.value = body.model_dump()
    row.updated_by = admin.username
    row.updated_at = now()
    audit(db, admin, "website.hero_update", "site", "hero", before=before, after=row.value)
    db.commit()
    return admin_site(admin, db)


# ---------------------------------------------------------------- Admin: downloads


def read_release(path: Path) -> dict | None:
    """Known fields of a release record, as plain values; None if unreadable."""
    try:
        if not path.is_file() or path.stat().st_size > MAX_RELEASE_FILE:
            return None
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return release_fields(data)


def release_fields(data: object) -> dict | None:
    if not isinstance(data, dict):
        return None
    text = ("platform", "version", "status", "fileName", "downloadUrl", "sha256")
    view = {k: str(data[k])[:200] for k in (*text, "publishedAt", "notes") if k in data}
    size = data.get("fileSizeBytes")
    view["fileSizeBytes"] = size if isinstance(size, int) else None
    return view


@router.get("/admin/v1/website/releases")
def releases(_: Reader):
    folder = os.environ.get("RELEASES_DIR", "")
    if not folder or not Path(folder).is_dir():
        return {"configured": False, "latest": None, "history": [], "files": []}
    root = Path(folder)
    history: list[dict] = []
    try:
        path = root / "history.json"
        if path.is_file() and path.stat().st_size <= MAX_RELEASE_FILE:
            raw = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(raw, list):
                history = [r for r in (release_fields(x) for x in raw[-50:]) if r]
    except (OSError, ValueError):
        history = []
    files = []
    for entry in sorted(root.glob("*.zip"), key=lambda p: p.stat().st_mtime, reverse=True)[:50]:
        stat = entry.stat()
        files.append(
            {
                "name": entry.name,
                "size": stat.st_size,
                "modified_at": datetime.fromtimestamp(stat.st_mtime, UTC),
            }
        )
    return {
        "configured": True,
        "latest": read_release(root / "latest.json"),
        "history": list(reversed(history)),
        "files": files,
    }


# ---------------------------------------------------------------- Public (site)


def visible(db: Session):
    return (
        select(SiteNews)
        .where(SiteNews.status == "published", SiteNews.publish_at <= now())
        .order_by(SiteNews.pinned.desc(), SiteNews.publish_at.desc())
    )


@router.get("/v1/public/news")
def public_news(
    db: Db,
    response: Response,
    category: Category | None = None,
    limit: int = Query(default=50, ge=1, le=100),
):
    query = visible(db)
    if category:
        query = query.where(SiteNews.category == category)
    rows = db.scalars(query.limit(limit))
    response.headers["Cache-Control"] = CACHE
    return {"news": [public_view(p) for p in rows]}


@router.get("/v1/public/news/{slug}")
def public_post(slug: str, db: Db, response: Response):
    post = db.scalar(visible(db).where(SiteNews.slug == slug))
    if post is None:
        raise HTTPException(404, "Post not found")
    response.headers["Cache-Control"] = CACHE
    return public_view(post, full=True)


@router.get("/v1/public/site")
def public_site(db: Db, response: Response):
    response.headers["Cache-Control"] = CACHE
    return {"hero": hero(db)[0]}
