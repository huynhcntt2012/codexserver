-- Pet skins (apps/practice/assets/cosmetics/pets, docs/PRACTICE.md): the owner rides
-- the pet in practice and online rounds; it is the Q mount (docs/BATTLE_ITEMS.md).
-- pet_bunny keeps its id and price and gets its bunny art.
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/013_pets.sql
-- then upload the icons: python -m app.admin_cli import-icons <assets folder>
UPDATE item_catalog
SET description = 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', icon = 'cosmetics/pets/bunny/idle/01.png', updated_by = 'seed', updated_at = now()
WHERE id = 'pet_bunny' AND icon IN ('items/heart.png', 'cosmetics/pets/bunny/idle/01.png');
INSERT INTO item_catalog (id, name, category, rarity, description, price, currency, quantity, icon, status, updated_by, updated_at) VALUES
    ('pet_dragon', 'Rồng Lửa Nhỏ', 'pet', 'legendary', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 220, 'gem', 1, 'cosmetics/pets/dragon/idle/01.png', 'published', 'seed', now()),
    ('pet_sheep', 'Cừu Sao Hồng', 'pet', 'rare', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 100, 'gem', 1, 'cosmetics/pets/sheep/idle/01.png', 'published', 'seed', now()),
    ('pet_deer', 'Tuần Lộc Chuông Vàng', 'pet', 'epic', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 150, 'gem', 1, 'cosmetics/pets/deer/idle/01.png', 'published', 'seed', now()),
    ('pet_alpaca', 'Lạc Đà Bông Trăng Xanh', 'pet', 'epic', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 150, 'gem', 1, 'cosmetics/pets/alpaca/idle/01.png', 'published', 'seed', now()),
    ('pet_cat', 'Mèo Tam Thể', 'pet', 'rare', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 100, 'gem', 1, 'cosmetics/pets/cat/idle/01.png', 'published', 'seed', now()),
    ('pet_corgi', 'Cún Corgi', 'pet', 'rare', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 100, 'gem', 1, 'cosmetics/pets/corgi/idle/01.png', 'published', 'seed', now()),
    ('pet_dino', 'Khủng Long Lá', 'pet', 'epic', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 160, 'gem', 1, 'cosmetics/pets/dino/idle/01.png', 'published', 'seed', now()),
    ('pet_turtle', 'Rùa Kem Anh Đào', 'pet', 'epic', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 160, 'gem', 1, 'cosmetics/pets/turtle/idle/01.png', 'published', 'seed', now()),
    ('pet_fox', 'Cáo Lá Xanh', 'pet', 'common', 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', 4000, 'gold', 1, 'cosmetics/pets/fox/idle/01.png', 'published', 'seed', now())
ON CONFLICT (id) DO NOTHING;
-- Rows from the first version of this file said the pet walks beside its owner.
UPDATE item_catalog SET description = 'Thú cưỡi trong trận: +25% tốc độ, đỡ 1 đòn', updated_by = 'seed', updated_at = now()
WHERE category = 'pet' AND description = 'Pet đi theo bạn trong trận; bấm Q để cưỡi';
