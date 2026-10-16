-- Admin portal (P0/P1): admin accounts, audit log, sanctions, item catalog seeded
-- from the game's item data, events, giftcodes and shop offers. Fresh volumes apply
-- it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/004_admin.sql
BEGIN;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ;
ALTER TABLE accounts ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS accounts_created_at ON accounts (created_at);
CREATE INDEX IF NOT EXISTS accounts_last_login_at ON accounts (last_login_at);
CREATE TABLE IF NOT EXISTS admin_users (
    id VARCHAR(36) PRIMARY KEY,
    username VARCHAR(32) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    role VARCHAR(16) NOT NULL CHECK (role IN ('owner', 'operator', 'viewer')),
    totp_secret VARCHAR(64),
    totp_pending VARCHAR(64),
    disabled BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL,
    last_login_at TIMESTAMPTZ
);
CREATE TABLE IF NOT EXISTS admin_audit_logs (
    id BIGSERIAL PRIMARY KEY,
    actor_admin_id VARCHAR(36),
    actor_name VARCHAR(32) NOT NULL,
    action VARCHAR(64) NOT NULL,
    target_type VARCHAR(32) NOT NULL,
    target_id VARCHAR(64) NOT NULL,
    reason VARCHAR(500) NOT NULL DEFAULT '',
    detail TEXT NOT NULL DEFAULT '{}',
    created_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS admin_audit_target ON admin_audit_logs (target_id);
CREATE INDEX IF NOT EXISTS admin_audit_action ON admin_audit_logs (action);
CREATE TABLE IF NOT EXISTS account_sanctions (
    id VARCHAR(36) PRIMARY KEY,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    kind VARCHAR(16) NOT NULL,
    reason VARCHAR(500) NOT NULL,
    created_by VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS account_sanctions_account ON account_sanctions (account_id);
CREATE TABLE IF NOT EXISTS item_catalog (
    id VARCHAR(64) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    category VARCHAR(16) NOT NULL,
    rarity VARCHAR(16) NOT NULL,
    description VARCHAR(200) NOT NULL DEFAULT '',
    price INTEGER NOT NULL DEFAULT 0 CHECK (price >= 0),
    currency VARCHAR(8) NOT NULL DEFAULT 'gold',
    duration_days INTEGER,
    icon VARCHAR(120),
    status VARCHAR(12) NOT NULL DEFAULT 'draft',
    updated_by VARCHAR(32) NOT NULL DEFAULT 'system',
    updated_at TIMESTAMPTZ NOT NULL
);
INSERT INTO item_catalog (id, name, category, rarity, description, price, currency, icon, status, updated_by, updated_at) VALUES
    ('bomb_basic_pack', 'Bom thường ×5', 'consumable', 'common', 'Tăng tồn kho vật phẩm trước trận', 500, 'gold', 'bombs/strong_black.png', 'published', 'seed', now()),
    ('speed_shoes', 'Giày tăng tốc ×5', 'consumable', 'common', 'Vật phẩm dùng trong trận', 800, 'gold', 'items/shoe.png', 'published', 'seed', now()),
    ('blue_shield', 'Khiên bảo vệ ×5', 'consumable', 'rare', 'Bảo vệ trong thời gian ngắn', 50, 'gem', 'items/shield.png', 'published', 'seed', now()),
    ('revive_heart', 'Tim hồi sinh ×3', 'consumable', 'common', 'Hồi sinh ở chế độ hỗ trợ', 1000, 'gold', 'items/heart.png', 'published', 'seed', now()),
    ('flame_boost', 'Lửa mạnh ×5', 'consumable', 'rare', 'Tăng tầm nổ trong trận', 70, 'gem', 'items/flame.png', 'published', 'seed', now()),
    ('mystery_box', 'Hộp bí ẩn', 'consumable', 'rare', 'Quà ngẫu nhiên giả lập', 60, 'gem', 'items/mystery.png', 'published', 'seed', now()),
    ('outfit_mimi', 'Bộ đồ MIMI', 'outfit', 'legendary', 'Trang phục nhân vật MIMI', 150, 'gem', 'characters/portraits/mimi.png', 'published', 'seed', now()),
    ('outfit_bombo', 'Bộ đồ BOMBO', 'outfit', 'rare', 'Trang phục xanh nổi bật', 120, 'gem', 'characters/portraits/bombo.png', 'published', 'seed', now()),
    ('outfit_kai', 'Bộ đồ KAI', 'outfit', 'legendary', 'Phong cách xanh lá dễ thương', 150, 'gem', 'characters/portraits/kai.png', 'published', 'seed', now()),
    ('bomb_skin_classic', 'Bom cổ điển', 'bomb_skin', 'common', 'Skin bom màu xanh', 400, 'gold', 'bombs/classic_blue.png', 'published', 'seed', now()),
    ('bomb_skin_black', 'Bom đen cổ điển', 'bomb_skin', 'rare', 'Skin bom đen quý hiếm', 65, 'gem', 'bombs/strong_black.png', 'published', 'seed', now()),
    ('bomb_skin_water', 'Bom nước', 'bomb_skin', 'rare', 'Skin bom xanh nước', 85, 'gem', 'bombs/water_blue.png', 'published', 'seed', now()),
    ('effect_fire', 'Nổ tia lửa', 'effect', 'common', 'Hiệu ứng nổ lửa', 500, 'gold', 'items/flame.png', 'published', 'seed', now()),
    ('effect_ice', 'Nổ băng giá', 'effect', 'rare', 'Hiệu ứng nổ băng', 100, 'gem', 'bombs/ice.png', 'published', 'seed', now()),
    ('effect_star', 'Nổ sao vàng', 'effect', 'legendary', 'Hiệu ứng lấp lánh hình sao', 100, 'gem', 'bombs/star.png', 'published', 'seed', now()),
    ('pet_bunny', 'Pet thỏ bông', 'pet', 'rare', 'Vật nuôi mang tính trang trí', 80, 'gem', 'items/heart.png', 'published', 'seed', now()),
    ('accessory_heart', 'Huy hiệu trái tim', 'accessory', 'rare', 'Phụ kiện trang trí', 900, 'gold', 'items/heart.png', 'published', 'seed', now()),
    ('hat_ice', 'Mũ băng tuyết', 'hat', 'rare', 'Phụ kiện đầu thời trang', 95, 'gem', 'items/ice.png', 'published', 'seed', now())
ON CONFLICT (id) DO NOTHING;
CREATE TABLE IF NOT EXISTS events (
    id VARCHAR(36) PRIMARY KEY,
    name VARCHAR(80) NOT NULL,
    kind VARCHAR(16) NOT NULL,
    description VARCHAR(500) NOT NULL DEFAULT '',
    status VARCHAR(12) NOT NULL DEFAULT 'draft',
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ NOT NULL CHECK (end_at > start_at),
    reward_items TEXT NOT NULL DEFAULT '[]',
    created_by VARCHAR(32) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS events_schedule ON events (status, start_at, end_at);
CREATE TABLE IF NOT EXISTS giftcodes (
    id VARCHAR(36) PRIMARY KEY,
    code VARCHAR(32) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL,
    reward_items TEXT NOT NULL DEFAULT '[]',
    max_redemptions INTEGER NOT NULL CHECK (max_redemptions > 0),
    starts_at TIMESTAMPTZ NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(12) NOT NULL DEFAULT 'active',
    created_by VARCHAR(32) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE IF NOT EXISTS giftcode_redemptions (
    id VARCHAR(36) PRIMARY KEY,
    giftcode_id VARCHAR(36) NOT NULL REFERENCES giftcodes(id) ON DELETE CASCADE,
    account_id VARCHAR(36) NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE (giftcode_id, account_id)
);
CREATE TABLE IF NOT EXISTS shop_offers (
    id VARCHAR(36) PRIMARY KEY,
    item_id VARCHAR(64) NOT NULL REFERENCES item_catalog(id),
    price INTEGER NOT NULL CHECK (price >= 0),
    currency VARCHAR(8) NOT NULL,
    discount_percent INTEGER NOT NULL DEFAULT 0 CHECK (discount_percent BETWEEN 0 AND 90),
    status VARCHAR(12) NOT NULL DEFAULT 'draft',
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ,
    updated_by VARCHAR(32) NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
COMMIT;
