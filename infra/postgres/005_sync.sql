-- Admin <-> client sync: presence, item art, server wallet + ledger, consumable stock,
-- rooms and match history. Fresh volumes apply it automatically; on an existing
-- volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/005_sync.sql
BEGIN;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS accounts_last_seen_at ON accounts (last_seen_at);
ALTER TABLE item_catalog ADD COLUMN IF NOT EXISTS icon_sha256 VARCHAR(64);
CREATE TABLE IF NOT EXISTS item_assets (
    sha256 VARCHAR(64) PRIMARY KEY,
    content BYTEA NOT NULL,
    content_type VARCHAR(32) NOT NULL,
    size INTEGER NOT NULL,
    width INTEGER NOT NULL,
    height INTEGER NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS wallets (
    account_id VARCHAR(36) PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    gold BIGINT NOT NULL DEFAULT 0 CHECK (gold >= 0),
    gem BIGINT NOT NULL DEFAULT 0 CHECK (gem >= 0),
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS wallet_ledger (
    id BIGSERIAL PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    currency VARCHAR(8) NOT NULL,
    delta BIGINT NOT NULL,
    balance_after BIGINT NOT NULL CHECK (balance_after >= 0),
    kind VARCHAR(16) NOT NULL,
    reference VARCHAR(120) NOT NULL UNIQUE,
    item_id VARCHAR(64),
    amount_vnd INTEGER,
    note VARCHAR(300) NOT NULL DEFAULT '',
    actor VARCHAR(32) NOT NULL DEFAULT 'player',
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS wallet_ledger_account ON wallet_ledger (account_id, id);
CREATE INDEX IF NOT EXISTS wallet_ledger_kind ON wallet_ledger (kind, created_at);
CREATE TABLE IF NOT EXISTS inventory_stock (
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    item_id VARCHAR(64) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    PRIMARY KEY (account_id, item_id)
);
CREATE TABLE IF NOT EXISTS game_rooms (
    id VARCHAR(80) PRIMARY KEY,
    source VARCHAR(10) NOT NULL,
    room_id VARCHAR(64) NOT NULL,
    creator_id VARCHAR(36) REFERENCES accounts(id) ON DELETE SET NULL,
    creator_name VARCHAR(24) NOT NULL DEFAULT '',
    status VARCHAR(10) NOT NULL DEFAULT 'waiting',
    map_name VARCHAR(40) NOT NULL DEFAULT '',
    players INTEGER NOT NULL DEFAULT 0,
    max_players INTEGER NOT NULL DEFAULT 8,
    rounds INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL,
    closed_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS game_rooms_creator ON game_rooms (creator_id);
CREATE INDEX IF NOT EXISTS game_rooms_created ON game_rooms (created_at);
CREATE TABLE IF NOT EXISTS matches (
    id VARCHAR(36) PRIMARY KEY,
    room_key VARCHAR(80) NOT NULL,
    source VARCHAR(10) NOT NULL,
    round INTEGER NOT NULL,
    map_name VARCHAR(40) NOT NULL DEFAULT '',
    verified BOOLEAN NOT NULL DEFAULT FALSE,
    winner_name VARCHAR(24),
    duration_ms INTEGER NOT NULL DEFAULT 0,
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ NOT NULL,
    UNIQUE (room_key, round)
);
CREATE INDEX IF NOT EXISTS matches_ended ON matches (ended_at);
CREATE TABLE IF NOT EXISTS match_participants (
    id BIGSERIAL PRIMARY KEY,
    match_id VARCHAR(36) NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
    account_id VARCHAR(36) REFERENCES accounts(id) ON DELETE SET NULL,
    name VARCHAR(24) NOT NULL,
    is_bot BOOLEAN NOT NULL DEFAULT FALSE,
    hero VARCHAR(24) NOT NULL DEFAULT '',
    placement INTEGER NOT NULL,
    kills INTEGER NOT NULL DEFAULT 0,
    bombs INTEGER NOT NULL DEFAULT 0,
    items INTEGER NOT NULL DEFAULT 0,
    score INTEGER NOT NULL DEFAULT 0,
    survived_ms INTEGER NOT NULL DEFAULT 0,
    winner BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX IF NOT EXISTS match_participants_account ON match_participants (account_id);
CREATE INDEX IF NOT EXISTS match_participants_match ON match_participants (match_id);
COMMIT;
