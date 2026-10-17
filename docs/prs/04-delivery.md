Adds Docker images and Compose services for the arena, API, PostgreSQL and Redis, with healthchecks and loopback defaults. GitHub Actions validates lint, tests, builds and the real Godot multiplayer flow. A separate manually triggered workflow publishes versioned images to GHCR. Ubuntu setup, backup, rollback, protocol and license documentation are included.

Validation: both application images built locally; all four Compose services became healthy. Thirteen Node tests, five Python tests and the two-client Godot smoke passed. The client resource pack exported successfully with copyright notices. See `docs/VALIDATION.md` for evidence and limitations.

Configure fresh secrets in `.env`, then run `docker compose up -d --build --wait`. Production deployment is not triggered automatically. This PR depends on the Godot client PR; GitHub Actions results must be reviewed separately from local validation.
