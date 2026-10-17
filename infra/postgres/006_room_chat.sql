-- Room chat: messages scoped to one game room, readable only by its members.
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/006_room_chat.sql
BEGIN;
ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS room_key VARCHAR(80);
CREATE INDEX IF NOT EXISTS chat_messages_room ON chat_messages (room_key, id);
CREATE TABLE IF NOT EXISTS game_room_members (
    room_key VARCHAR(80) NOT NULL,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    PRIMARY KEY (room_key, account_id)
);
COMMIT;
