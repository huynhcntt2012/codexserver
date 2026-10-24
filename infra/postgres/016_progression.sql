-- Match EXP and character levels (apps/api/app/progression.py, docs/PROGRESSION.md).
-- One award per (match, player); one ledger row per (source, player).
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/016_progression.sql
BEGIN;
CREATE TABLE IF NOT EXISTS xp_rule_sets (
    id VARCHAR(36) PRIMARY KEY,
    version INTEGER NOT NULL UNIQUE,
    status VARCHAR(10) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
    note VARCHAR(300) NOT NULL DEFAULT '',
    config JSON NOT NULL,
    created_by VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    published_by VARCHAR(32),
    published_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS xp_rule_sets_published ON xp_rule_sets (published_at);
CREATE TABLE IF NOT EXISTS player_progression (
    account_id VARCHAR(36) PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    level INTEGER NOT NULL DEFAULT 1 CHECK (level >= 1),
    xp_in_level INTEGER NOT NULL DEFAULT 0 CHECK (xp_in_level >= 0),
    total_xp INTEGER NOT NULL DEFAULT 0 CHECK (total_xp >= 0),
    curve_version INTEGER NOT NULL DEFAULT 1,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS match_xp_awards (
    id VARCHAR(36) PRIMARY KEY,
    match_id VARCHAR(120) NOT NULL,
    account_id VARCHAR(36) NOT NULL,
    mode VARCHAR(10) NOT NULL CHECK (mode IN ('PVP', 'PVE_BOSS')),
    result VARCHAR(8) NOT NULL,
    eligible BOOLEAN NOT NULL DEFAULT FALSE,
    reason VARCHAR(16) NOT NULL DEFAULT '',
    ruleset_id VARCHAR(36) NOT NULL,
    ruleset_version INTEGER NOT NULL,
    stats JSON NOT NULL,
    lines JSON NOT NULL,
    raw_exp INTEGER NOT NULL DEFAULT 0,
    cap INTEGER NOT NULL DEFAULT 0,
    capped_base_exp INTEGER NOT NULL DEFAULT 0,
    event_multiplier DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    daily_factor DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    awarded_exp INTEGER NOT NULL DEFAULT 0 CHECK (awarded_exp >= 0),
    level_before INTEGER NOT NULL DEFAULT 1,
    level_after INTEGER NOT NULL DEFAULT 1,
    progress_before INTEGER NOT NULL DEFAULT 0,
    progress_after INTEGER NOT NULL DEFAULT 0,
    day VARCHAR(10) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (match_id, account_id)
);
CREATE INDEX IF NOT EXISTS match_xp_awards_account ON match_xp_awards (account_id, created_at);
CREATE INDEX IF NOT EXISTS match_xp_awards_day ON match_xp_awards (day);
CREATE TABLE IF NOT EXISTS player_xp_ledger (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL,
    source_type VARCHAR(20) NOT NULL CHECK (source_type IN ('MATCH', 'MANUAL_ADJUSTMENT')),
    source_id VARCHAR(120) NOT NULL,
    amount INTEGER NOT NULL CHECK (amount > 0),
    total_after INTEGER NOT NULL,
    reason VARCHAR(300) NOT NULL DEFAULT '',
    created_by VARCHAR(32) NOT NULL DEFAULT 'system',
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (source_type, source_id, account_id)
);
CREATE INDEX IF NOT EXISTS player_xp_ledger_account ON player_xp_ledger (account_id, created_at);
COMMIT;
