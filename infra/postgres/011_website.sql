-- Website CMS (apps/api/app/website.py, docs/PORTAL.md): news posts and hero text
-- for the promotion site (/), edited in the Admin Portal "Website" module.
-- Fresh volumes apply it automatically; on an existing volume run it once:
-- docker compose exec -T postgres psql -U suni -d suni < infra/postgres/011_website.sql
BEGIN;
CREATE TABLE IF NOT EXISTS site_news (
    id VARCHAR(36) PRIMARY KEY,
    slug VARCHAR(80) NOT NULL UNIQUE,
    title VARCHAR(120) NOT NULL,
    category VARCHAR(16) NOT NULL,
    excerpt VARCHAR(300) NOT NULL DEFAULT '',
    body JSON NOT NULL,
    image VARCHAR(120) NOT NULL,
    pinned BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(12) NOT NULL DEFAULT 'draft',
    publish_at TIMESTAMPTZ NOT NULL,
    created_by VARCHAR(32) NOT NULL DEFAULT 'system',
    updated_by VARCHAR(32) NOT NULL DEFAULT 'system',
    created_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
);
CREATE INDEX IF NOT EXISTS site_news_public ON site_news (status, publish_at);
CREATE TABLE IF NOT EXISTS site_settings (
    key VARCHAR(32) PRIMARY KEY,
    value JSON NOT NULL,
    updated_by VARCHAR(32) NOT NULL DEFAULT 'system',
    updated_at TIMESTAMPTZ NOT NULL
);
-- The posts that shipped in apps/web/public/data/news.json (kept as fallback).
INSERT INTO site_news (id, slug, title, category, excerpt, body, image, pinned, status, publish_at, created_by, updated_by, created_at, updated_at) VALUES
    ('ce862302-a466-59a3-908b-3cdfedc6dcca', 'vat-pham-trong-tran', 'Cập nhật: 6 vật phẩm chiến thuật và thú cưỡi', 'Cập nhật', 'Thanh CÁ NHÂN 1–6, nút Ctrl để dùng vật phẩm và phím Q để cưỡi thú. Có ở cả Luyện tập và Online.', '["Trận đấu có thêm thanh vật phẩm CÁ NHÂN với 6 ô: Bom ném xa, Phi tiêu kích nổ, Khiên bảo vệ, Giày tăng tốc, Bom đóng băng và Găng đẩy bom.", "Nhấn phím 1–6 để chọn, Ctrl để dùng theo hướng nhân vật đang nhìn. Mỗi vật phẩm có thời gian hồi riêng, số lượng lấy từ kho đồ đã mua trong Cửa hàng.", "Sở hữu một thú nuôi? Nhấn Q để cưỡi: tăng 25% tốc độ và đỡ cho bạn một lần trúng bom.", "Trong trận Online, máy chủ kiểm tra mọi lần dùng vật phẩm, nên mọi người đều thấy cùng một kết quả."]', '/img/gameplay-online.webp', TRUE, 'published', '2026-10-18T00:00:00+07:00', 'seed', 'seed', now(), now()),
    ('28c86b2e-9d8c-5699-a25a-7723f26c39b0', 'moi-ban-be-va-phong-luyen-tap', 'Mời bạn bè vào trận và luyện tập cùng bot', 'Cập nhật', 'Gửi lời mời từ phòng chờ, bạn bè bấm VÀO là chơi chung. Phòng luyện tập cho phép bạn bè thay ghế bot.', '["Trong phòng chờ, nút MỜI BẠN hiện danh sách bạn bè đang online. Người nhận thấy thẻ mời ở góc màn hình và vào thẳng phòng.", "Phòng Luyện tập giờ có thể mời bạn: bạn và tối đa 3 bot do máy chủ điều khiển, bạn bè nhận lời sẽ thay ghế một bot."]', '/img/news-invite.webp', FALSE, 'published', '2026-10-17T00:00:00+07:00', 'seed', 'seed', now(), now()),
    ('4ffaf456-86eb-597c-8018-482171a89afb', 'nhiem-vu-va-su-kien', 'Nhiệm vụ hằng ngày, chương truyện và Cửa hàng Sự kiện', 'Sự kiện', 'Làm nhiệm vụ mỗi ngày để nhận vàng, sưu tầm Vé Sao trong sự kiện và đổi quà ở Cửa hàng Sự kiện.', '["Mở cửa sổ Nhiệm vụ để xem nhiệm vụ ngày và tuần. Tiến độ được tính từ các trận đấu đã được máy chủ xác nhận.", "Các sự kiện có chương truyện theo bản đồ, nhiệm vụ riêng và cửa hàng đổi Vé Sao lấy trang phục, vật phẩm."]', '/img/news-event.webp', FALSE, 'published', '2026-10-16T00:00:00+07:00', 'seed', 'seed', now(), now()),
    ('0b5af314-0b27-5934-8b9b-dff22ddfd581', '12-ban-do-moi', '12 bản đồ mới khổ lớn 17×13', 'Cập nhật', 'Từ Tiệm Bánh Mây tới Cung Điện Trăng: mỗi bản đồ có câu chuyện, chướng ngại và hiệu ứng nổ riêng.', '["Thêm 12 bản đồ khổ 17×13 cho Luyện tập và phòng Online, nâng tổng số lên 15 bản đồ.", "Mỗi bản đồ có chủ đề, loại bom, hiệu ứng nổ và câu chuyện riêng. Chọn bản đồ ngay ở sảnh chính."]', '/img/news-maps.webp', FALSE, 'published', '2026-10-14T00:00:00+07:00', 'seed', 'seed', now(), now()),
    ('04a87ed4-0625-5169-bc9a-6aa183003012', 'huong-dan-nguoi-moi', 'Hướng dẫn chơi cho người mới', 'Hướng dẫn', 'Thao tác cơ bản, mẹo đặt bom và cách dùng vật phẩm để thắng trận đầu tiên.', '["Di chuyển bằng WASD hoặc phím mũi tên, nhấn Space để đặt bom nước. Bom nổ theo hình chữ thập và phá thùng gỗ.", "Đừng đứng cùng hàng hoặc cột với quả bom sắp nổ. Luôn để sẵn một lối thoát trước khi đặt bom.", "Thùng vỡ có thể rơi vật phẩm: thêm bom, tăng tầm nổ, tăng tốc độ. Xem trang Hướng dẫn để biết đầy đủ phím tắt."]', '/img/gameplay-practice.webp', FALSE, 'published', '2026-10-12T00:00:00+07:00', 'seed', 'seed', now(), now())
ON CONFLICT (slug) DO NOTHING;
COMMIT;
