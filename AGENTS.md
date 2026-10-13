# Repository Guidelines

## Project Structure & Module Organization

Suni Bomb Arena uses `apps/client` (Godot 4.4.1), `apps/arena` (Colyseus + TypeScript), and `apps/api` (FastAPI). Infrastructure is in `infra`, automation in `scripts` and `.github`, and runbooks in `docs`. Keep all project files here. Read `README.md` and `docs/ARCHITECTURE.md` before changing protocols.

## Build, Test, and Development Commands

Use Node 22.13+, Python 3.12, uv 0.13.0 and Godot 4.4.1. Commands:

- `npm ci`, `npm run lint`, `npm test`, `npm run build`, `npm run format:check`.
- `uv sync --locked --project apps/api`; `uv run --project apps/api ruff check apps/api`.
- `cd apps/api && uv run pytest`.
- `GODOT=/path/to/godot python3 scripts/check-godot.py`.
- `docker compose up -d --build --wait`, then `godot --headless --path apps/client --script res://tests/smoke.gd`.

Useful checks available now:

- `git status --short`: inspect pending changes.
- `git diff --check`: detect whitespace errors in tracked changes.
- `git diff --stat`: review the scope of tracked changes.

## Coding Style & Naming Conventions

Use strict TypeScript with ESLint/Prettier, Ruff for Python, and tabs for GDScript. Keep modules focused on one responsibility. Clients send intent only: never accept client positions, bomb timers, damage, VIP grants or match outcomes. Keep Markdown concise with descriptive headings and fenced command examples.

## Testing Guidelines

Use node:test for simulation and real WebSocket tests, pytest for API tests and a real Godot headless smoke test. Cover chain reactions, collision, simultaneous deaths, capacity and invalid credentials. Protocol/dependency upgrades require both network.test.ts and Godot smoke. Document checks honestly; do not claim unavailable validation ran.

## Commit & Pull Request Guidelines

There is no commit history from which to infer a message convention. Use concise, imperative subjects, such as `Add initial server configuration`, and keep commits focused. Pull requests should explain the purpose, summarize behavior changes, and report validation performed or unavailable. Link relevant issues; include screenshots when changing a user interface.

## Security & Configuration

Keep credentials, local environment files, generated artifacts and databases out of Git. Keep network defaults on loopback. No real payment flows in phase 1. Never copy source/assets/names/logos/music/characters from Boom Online. Add only commercially compatible dependencies and verified assets, preserving license and copyright notices in THIRD_PARTY_NOTICES.md. Use original placeholders for unverified assets. Do not silently change Redis license families. Follow docs/PULL_REQUESTS.md for small PRs; never automatically merge or deploy production.
