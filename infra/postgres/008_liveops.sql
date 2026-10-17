-- Missions and LiveOps events (apps/api/app/liveops.py, docs/LIVEOPS.md).
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/008_liveops.sql
-- then add the default missions: docker compose exec api python -m app.admin_cli seed-quests
BEGIN;
ALTER TABLE events ADD COLUMN IF NOT EXISTS claim_end_at TIMESTAMPTZ;
ALTER TABLE events ADD COLUMN IF NOT EXISTS config JSON;
ALTER TABLE events ADD COLUMN IF NOT EXISTS version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE game_rooms ADD COLUMN IF NOT EXISTS map_id VARCHAR(24) NOT NULL DEFAULT '';
ALTER TABLE matches ADD COLUMN IF NOT EXISTS map_id VARCHAR(24) NOT NULL DEFAULT '';
CREATE TABLE IF NOT EXISTS quest_definitions (
    key VARCHAR(32) PRIMARY KEY,
    scope VARCHAR(8) NOT NULL,
    title VARCHAR(80) NOT NULL,
    description VARCHAR(200) NOT NULL DEFAULT '',
    objectives JSON NOT NULL,
    rewards JSON NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    sort INTEGER NOT NULL DEFAULT 0,
    updated_by VARCHAR(32) NOT NULL DEFAULT 'system',
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS quest_progress (
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    quest_key VARCHAR(80) NOT NULL,
    period_key VARCHAR(16) NOT NULL,
    state JSON NOT NULL,
    status VARCHAR(12) NOT NULL DEFAULT 'in_progress',
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (account_id, quest_key, period_key)
);
CREATE TABLE IF NOT EXISTS quest_match_log (
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    match_id VARCHAR(36) NOT NULL,
    source VARCHAR(10) NOT NULL,
    day VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (account_id, match_id)
);
CREATE INDEX IF NOT EXISTS quest_match_log_day ON quest_match_log (account_id, source, day);
CREATE TABLE IF NOT EXISTS reward_claims (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    grant_key VARCHAR(140) NOT NULL UNIQUE,
    quest_key VARCHAR(80) NOT NULL,
    event_id VARCHAR(36),
    rewards JSON NOT NULL,
    claimed_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS event_wallets (
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    event_id VARCHAR(36) NOT NULL,
    balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
    updated_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (account_id, event_id)
);
CREATE TABLE IF NOT EXISTS event_token_ledger (
    id SERIAL PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    event_id VARCHAR(36) NOT NULL,
    delta INTEGER NOT NULL,
    balance_after INTEGER NOT NULL,
    reason VARCHAR(12) NOT NULL,
    reference VARCHAR(140) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS event_shop_orders (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    event_id VARCHAR(36) NOT NULL,
    sku VARCHAR(32) NOT NULL,
    item_id VARCHAR(64) NOT NULL,
    cost INTEGER NOT NULL,
    reference VARCHAR(140) NOT NULL UNIQUE,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS event_shop_orders_sku ON event_shop_orders (event_id, sku, account_id);
CREATE TABLE IF NOT EXISTS event_versions (
    event_id VARCHAR(36) NOT NULL,
    version INTEGER NOT NULL,
    snapshot JSON NOT NULL,
    created_by VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (event_id, version)
);
COMMIT;
