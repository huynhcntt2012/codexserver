-- Battle items (apps/api/app/battle_items.py, docs/BATTLE_ITEMS.md).
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/010_battle_items.sql
BEGIN;
ALTER TABLE item_catalog ADD COLUMN IF NOT EXISTS quantity INTEGER NOT NULL DEFAULT 1;
-- "×N" packs now add N uses per purchase (they used to add 1).
UPDATE item_catalog SET quantity = 5 WHERE id IN ('bomb_basic_pack', 'speed_shoes', 'blue_shield', 'flame_boost') AND quantity = 1;
UPDATE item_catalog SET quantity = 3 WHERE id = 'revive_heart' AND quantity = 1;
INSERT INTO item_catalog (id, name, category, rarity, description, price, currency, quantity, icon, status, updated_by, updated_at) VALUES
    ('throw_bomb', 'Bom ném xa ×5', 'consumable', 'common', 'Ctrl: ném bom tới 3 ô theo hướng nhìn', 600, 'gold', 5, 'items/range.png', 'published', 'seed', now()),
    ('dart', 'Phi tiêu kích nổ ×5', 'consumable', 'rare', 'Ctrl: bay 5 ô, chạm bom là nổ ngay', 40, 'gem', 5, 'items/lightning.png', 'published', 'seed', now()),
    ('freeze_bomb', 'Bom đóng băng ×5', 'consumable', 'rare', 'Ctrl: làm chậm đối thủ vùng 3×3 trong 3 giây', 45, 'gem', 5, 'items/ice.png', 'published', 'seed', now()),
    ('push_glove', 'Găng đẩy bom ×5', 'consumable', 'common', 'Ctrl: đẩy quả bom phía trước trượt đi', 700, 'gold', 5, 'items/magnet.png', 'published', 'seed', now())
ON CONFLICT (id) DO NOTHING;
UPDATE item_catalog SET description = 'Ctrl: chặn 1 lần trúng bom (8 giây)' WHERE id = 'blue_shield';
UPDATE item_catalog SET description = 'Ctrl: +35% tốc độ trong 5 giây' WHERE id = 'speed_shoes';
CREATE TABLE IF NOT EXISTS item_uses (
    reference VARCHAR(120) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    item_id VARCHAR(64) NOT NULL,
    source VARCHAR(10) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
COMMIT;
