-- Boss raids (apps/api/app/boss.py, docs/BOSS.md). A boss event is an `events`
-- row (kind 'boss') whose config has a `boss` block; badges, quests and the shop
-- reuse the LiveOps tables (008_liveops.sql). These tables hold the raids.
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/014_boss.sql
BEGIN;
CREATE TABLE IF NOT EXISTS boss_raid_matches (
    id VARCHAR(120) PRIMARY KEY,
    event_id VARCHAR(36) NOT NULL,
    room_id VARCHAR(64) NOT NULL,
    boss_id VARCHAR(32) NOT NULL,
    map_id VARCHAR(24) NOT NULL DEFAULT '',
    result VARCHAR(8) NOT NULL CHECK (result IN ('WIN', 'LOSE', 'TIMEOUT', 'ABORT')),
    hp_max INTEGER NOT NULL,
    hp_left INTEGER NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL,
    private BOOLEAN NOT NULL DEFAULT FALSE,
    players INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS ix_boss_raid_matches_event_id ON boss_raid_matches (event_id, created_at);
CREATE TABLE IF NOT EXISTS boss_raid_participants (
    match_id VARCHAR(120) NOT NULL REFERENCES boss_raid_matches(id) ON DELETE CASCADE,
    account_id VARCHAR(36) NOT NULL,
    name VARCHAR(24) NOT NULL,
    damage INTEGER NOT NULL DEFAULT 0,
    support INTEGER NOT NULL DEFAULT 0,
    actions INTEGER NOT NULL DEFAULT 0,
    active_ms INTEGER NOT NULL DEFAULT 0,
    alive BOOLEAN NOT NULL DEFAULT FALSE,
    reward VARCHAR(12) NOT NULL DEFAULT 'none',
    reason VARCHAR(16) NOT NULL DEFAULT '',
    PRIMARY KEY (match_id, account_id)
);
CREATE INDEX IF NOT EXISTS ix_boss_raid_participants_account_id ON boss_raid_participants (account_id);
CREATE TABLE IF NOT EXISTS boss_reward_grants (
    id VARCHAR(36) PRIMARY KEY,
    match_id VARCHAR(120) NOT NULL REFERENCES boss_raid_matches(id) ON DELETE CASCADE,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    event_id VARCHAR(36) NOT NULL,
    kind VARCHAR(12) NOT NULL CHECK (kind IN ('full', 'consolation')),
    status VARCHAR(10) NOT NULL DEFAULT 'ELIGIBLE' CHECK (status IN ('ELIGIBLE', 'CLAIMED', 'EXPIRED')),
    rewards JSON NOT NULL,
    day VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    claimed_at TIMESTAMPTZ,
    UNIQUE (match_id, account_id, kind)
);
CREATE INDEX IF NOT EXISTS ix_boss_reward_grants_account_id ON boss_reward_grants (account_id, status);
CREATE INDEX IF NOT EXISTS ix_boss_reward_grants_event_id ON boss_reward_grants (event_id, account_id, kind, day);
COMMIT;
