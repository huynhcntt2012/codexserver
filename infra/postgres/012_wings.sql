-- Wings and halos (apps/practice/assets/cosmetics, docs/PRACTICE.md).
-- Halos use the existing "hat" slot; wings are the new "wings" category.
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/012_wings.sql
-- then upload the icons: python -m app.admin_cli import-icons <assets folder>
INSERT INTO item_catalog (id, name, category, rarity, description, price, currency, quantity, icon, status, updated_by, updated_at) VALUES
    ('halo_blue_angel', 'Hào quang Thiên Thần Xanh', 'hat', 'rare', 'Vòng hào quang lơ lửng trên đầu', 90, 'gem', 1, 'cosmetics/halos/blue_angel.png', 'published', 'seed', now()),
    ('halo_pink_heart', 'Hào quang Trái Tim Hồng', 'hat', 'rare', 'Vòng hào quang lơ lửng trên đầu', 90, 'gem', 1, 'cosmetics/halos/pink_heart.png', 'published', 'seed', now()),
    ('halo_red_flame', 'Hào quang Lửa Đỏ', 'hat', 'epic', 'Vòng hào quang lơ lửng trên đầu', 130, 'gem', 1, 'cosmetics/halos/red_flame.png', 'published', 'seed', now()),
    ('halo_golden_light', 'Hào quang Ánh Vàng', 'hat', 'epic', 'Vòng hào quang lơ lửng trên đầu', 130, 'gem', 1, 'cosmetics/halos/golden_light.png', 'published', 'seed', now()),
    ('halo_green_nature', 'Hào quang Lá Xanh', 'hat', 'rare', 'Vòng hào quang lơ lửng trên đầu', 110, 'gem', 1, 'cosmetics/halos/green_nature.png', 'published', 'seed', now()),
    ('halo_white_classic', 'Hào quang Trắng Cổ Điển', 'hat', 'common', 'Vòng hào quang lơ lửng trên đầu', 2000, 'gold', 1, 'cosmetics/halos/white_classic.png', 'published', 'seed', now()),
    ('wings_blue_angel', 'Cánh Thiên Thần Xanh', 'wings', 'rare', 'Đôi cánh sau lưng, vỗ khi di chuyển', 120, 'gem', 1, 'cosmetics/wings/blue_angel/idle/01.png', 'published', 'seed', now()),
    ('wings_pink_heart', 'Cánh Trái Tim Hồng', 'wings', 'rare', 'Đôi cánh sau lưng, vỗ khi di chuyển', 120, 'gem', 1, 'cosmetics/wings/pink_heart/idle/01.png', 'published', 'seed', now()),
    ('wings_red_flame', 'Cánh Lửa Đỏ', 'wings', 'epic', 'Đôi cánh sau lưng, vỗ khi di chuyển', 180, 'gem', 1, 'cosmetics/wings/red_flame/idle/01.png', 'published', 'seed', now()),
    ('wings_golden_light', 'Cánh Ánh Vàng', 'wings', 'epic', 'Đôi cánh sau lưng, vỗ khi di chuyển', 180, 'gem', 1, 'cosmetics/wings/golden_light/idle/01.png', 'published', 'seed', now()),
    ('wings_green_nature', 'Cánh Lá Xanh', 'wings', 'rare', 'Đôi cánh sau lưng, vỗ khi di chuyển', 150, 'gem', 1, 'cosmetics/wings/green_nature/idle/01.png', 'published', 'seed', now()),
    ('wings_white_classic', 'Cánh Trắng Cổ Điển', 'wings', 'common', 'Đôi cánh sau lưng, vỗ khi di chuyển', 3000, 'gold', 1, 'cosmetics/wings/white_classic/idle/01.png', 'published', 'seed', now())
ON CONFLICT (id) DO NOTHING;
