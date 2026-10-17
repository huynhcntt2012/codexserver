-- Room invites between friends (apps/api/app/invites.py).
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/009_invites.sql
BEGIN;
CREATE TABLE IF NOT EXISTS game_invites (
    id VARCHAR(36) PRIMARY KEY,
    sender_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    receiver_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    room_key VARCHAR(80) NOT NULL,
    room_id VARCHAR(64) NOT NULL,
    map_id VARCHAR(24) NOT NULL DEFAULT '',
    map_name VARCHAR(40) NOT NULL DEFAULT '',
    number INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(10) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS game_invites_receiver ON game_invites (receiver_id, status, expires_at);
CREATE INDEX IF NOT EXISTS game_invites_sender ON game_invites (sender_id, created_at);
COMMIT;
