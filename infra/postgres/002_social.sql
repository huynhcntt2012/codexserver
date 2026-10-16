-- Friends, guilds and chat. Fresh volumes apply it automatically; on an existing
-- volume run it once: docker compose exec -T postgres psql -U suni -d suni < infra/postgres/002_social.sql
BEGIN;
CREATE TABLE IF NOT EXISTS friend_requests (
    id VARCHAR(36) PRIMARY KEY,
    sender_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    receiver_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    status VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (sender_id, receiver_id)
);
CREATE TABLE IF NOT EXISTS guilds (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(24) NOT NULL UNIQUE
);
CREATE UNIQUE INDEX IF NOT EXISTS guilds_name_lower ON guilds (lower(name));
CREATE TABLE IF NOT EXISTS guild_members (
    account_id VARCHAR(36) PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    guild_id VARCHAR(36) NOT NULL REFERENCES guilds(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS chat_messages (
    id BIGSERIAL PRIMARY KEY,
    channel VARCHAR(10) NOT NULL,
    guild_id VARCHAR(36) REFERENCES guilds(id) ON DELETE CASCADE,
    sender_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    recipient_id VARCHAR(36) REFERENCES accounts(id) ON DELETE CASCADE,
    body VARCHAR(200) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS chat_messages_channel_id ON chat_messages (channel, id);
CREATE INDEX IF NOT EXISTS friend_requests_receiver ON friend_requests (receiver_id);
COMMIT;
