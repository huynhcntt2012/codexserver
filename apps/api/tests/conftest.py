import os

os.environ.setdefault("JWT_SECRET", "test-only-key-32-characters-long-do-not-deploy")
os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("REDIS_URL", "redis://localhost:6379/15")

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
