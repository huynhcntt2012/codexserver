-- Admin-made maps (draft -> published), served by GET /v1/maps.
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/007_maps.sql
BEGIN;
CREATE TABLE IF NOT EXISTS game_maps (
    id VARCHAR(24) PRIMARY KEY,
    name VARCHAR(40) NOT NULL,
    tier VARCHAR(16) NOT NULL,
    region VARCHAR(60) NOT NULL DEFAULT '',
    story VARCHAR(300) NOT NULL DEFAULT '',
    art JSON NOT NULL,
    layout JSON NOT NULL,
    status VARCHAR(12) NOT NULL DEFAULT 'draft',
    revision INTEGER NOT NULL DEFAULT 1,
    created_by VARCHAR(32) NOT NULL DEFAULT 'system',
    updated_by VARCHAR(32) NOT NULL DEFAULT 'system',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS game_maps_status ON game_maps (status);
COMMIT;
