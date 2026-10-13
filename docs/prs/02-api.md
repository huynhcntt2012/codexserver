Adds guest accounts, registration and login with Argon2 password hashing and signed JWTs. PostgreSQL stores accounts and default inventory; inventory and VIP endpoints read only the authenticated account. Redis limits authentication attempts. No payment integration or client-controlled VIP grants are introduced.

Validation: Ruff lint/format and five pytest tests passed locally in Python 3.12, including the Docker test target. The full-stack Godot smoke also used real PostgreSQL and Redis. Unit tests use SQLite and a mocked limiter.

Run `uv sync --locked --project apps/api`, `uv run --project apps/api ruff check apps/api`, then `cd apps/api && uv run pytest`. The initial SQL schema is applied only to a fresh PostgreSQL volume. This PR depends on the arena PR.
