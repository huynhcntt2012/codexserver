-- Email on accounts and password reset codes. Fresh volumes apply it automatically;
-- on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/003_recovery.sql
BEGIN;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS email VARCHAR(254);
CREATE UNIQUE INDEX IF NOT EXISTS accounts_email ON accounts (email);
CREATE TABLE IF NOT EXISTS password_resets (
    account_id VARCHAR(36) PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    code_hash VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 0
);
COMMIT;
