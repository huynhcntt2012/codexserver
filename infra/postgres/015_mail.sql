-- In-game mailbox (apps/api/app/mail.py, docs/MAIL.md). One row per message;
-- per-player read / claimed / deleted state is a receipt created on first touch.
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/015_mail.sql
BEGIN;
CREATE TABLE IF NOT EXISTS mail_messages (
    id VARCHAR(36) PRIMARY KEY,
    category VARCHAR(16) NOT NULL DEFAULT 'admin',
    sender VARCHAR(40) NOT NULL DEFAULT 'Ban điều hành',
    title VARCHAR(80) NOT NULL,
    body TEXT NOT NULL DEFAULT '',
    rewards JSON NOT NULL DEFAULT '[]',
    audience VARCHAR(8) NOT NULL DEFAULT 'all' CHECK (audience IN ('all', 'players')),
    targets JSON NOT NULL DEFAULT '[]',
    status VARCHAR(12) NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'recalled')),
    created_by VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS mail_messages_live ON mail_messages (status, expires_at);
CREATE TABLE IF NOT EXISTS mail_receipts (
    message_id VARCHAR(36) NOT NULL REFERENCES mail_messages(id) ON DELETE CASCADE,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ,
    claimed_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    PRIMARY KEY (message_id, account_id)
);
CREATE INDEX IF NOT EXISTS mail_receipts_account ON mail_receipts (account_id);
COMMIT;
