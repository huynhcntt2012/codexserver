# Admin portal

Trang quản trị game tại `https://boom.sunifactory.com/admin/` (local:
`http://127.0.0.1:8081/admin/`). Làm theo `Boom_Admin_v2.pdf`: không thay arena
Colyseus hay protocol v1, Admin Portal là lớp mở rộng trên stack hiện có.

## Kiến trúc

| Lớp       | Vị trí                                              | Ghi chú                                                                                                                                                                                                    |
| --------- | --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Admin UI  | `apps/admin` (Next.js 16, Pages Router, TypeScript) | Static export `basePath=/admin`, build trong `apps/web/Dockerfile`, CSP `script-src 'self'` như web                                                                                                        |
| Admin API | `apps/api/app/admin_auth.py`, `admin_api.py`        | FastAPI `/admin/v1/*`, nginx proxy `/admin/api/`                                                                                                                                                           |
| Dữ liệu   | `infra/postgres/004_admin.sql`                      | `admin_users`, `admin_audit_logs`, `account_sanctions`, `item_catalog` (seed 18 vật phẩm của game), `events`, `giftcodes`, `giftcode_redemptions`, `shop_offers`; thêm `accounts.created_at/last_login_at` |

Bảo mật: tài khoản admin tách riêng người chơi, token audience `suni-admin`
(token người chơi `suni-arena` không dùng được và ngược lại), hết hạn 4 giờ, lưu
trong `sessionStorage`. Mỗi request đọc lại admin từ DB nên khóa/hạ quyền có hiệu
lực ngay. Mật khẩu argon2, MFA TOTP tùy chọn, giới hạn 10 lần đăng nhập/5 phút.
Mọi thao tác ghi đều vào `admin_audit_logs` (không lưu mật khẩu/token).

| Vai trò  | Quyền                                                                     |
| -------- | ------------------------------------------------------------------------- |
| owner    | Toàn quyền, quản lý admin                                                 |
| operator | Vận hành: vật phẩm, sự kiện, giftcode, shop, tặng/thu hồi, khóa tài khoản |
| viewer   | Chỉ xem; email người chơi bị che                                          |

## Module

- **Dashboard / Báo cáo**: số liệu thật (tài khoản, đăng ký, đăng nhập gần nhất,
  chat, bang, bạn bè, giftcode, phòng chờ arena), xuất CSV. Không có doanh thu
  vì chưa có thanh toán thật.
- **Người chơi**: tìm kiếm, hồ sơ, kho đồ, chat gần đây, lịch sử khóa, nhật ký.
  Khóa có thời hạn/vĩnh viễn chặn `/v1/login` và mọi API tài khoản ngay; arena
  chưa kiểm tra lại giữa trận. Tặng/thu hồi vật phẩm, xóa tin nhắn (có lý do).
- **Vật phẩm**: danh mục, tạo bản nháp, sửa, phát hành, ẩn.
- **Sự kiện**: tạo theo 3 bước, lên lịch, phát hành, tạm dừng, tiếp tục. Chưa có
  worker phát thưởng tự động hay thống kê tham gia.
- **Giftcode**: mã tự đặt hoặc ngẫu nhiên, giới hạn lượt, hạn dùng, bật/tắt.
  Người chơi nhập qua `POST /v1/giftcodes/redeem` (mỗi tài khoản một lần, khóa
  hàng khi đếm lượt), vật phẩm vào kho.
- **Shop**: ưu đãi theo vật phẩm đã phát hành, giảm giá, thời gian bán; danh sách
  công khai `GET /v1/shop/offers`. Chưa có ví/đơn hàng.
- **Trận đấu**: phòng đang chờ lấy từ arena `GET /rooms` bằng token dịch vụ 1 phút.
  Chưa có lịch sử trận (cần match ingestion).
- **Kinh tế**: sổ tặng/thu hồi vật phẩm. Chưa có ví vàng/kim cương phía server.
- **Server**: tình trạng API, PostgreSQL, Redis, arena, chế độ email.
- **Cài đặt**: đổi mật khẩu, bật MFA, quản lý admin (owner), nhật ký audit.

## Đồng bộ admin ↔ client (005)

| Phần                   | Cách làm                                                                                                                                                                                                                                                                                                                          |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ảnh vật phẩm           | Admin tải PNG (≤ 10 MB, 16–2048 px) ở trang Vật phẩm; lưu theo sha256 trong `item_assets`. `GET /v1/catalog` trả danh sách đã phát hành kèm `icon_sha256` và ETag; `GET /v1/assets/<sha>.png` cache vĩnh viễn (`immutable`, Cloudflare cache được).                                                                               |
| Client PC              | `scripts/catalog_sync.gd`: khi mở game và khi đăng nhập hỏi catalog với `If-None-Match` (không đổi = 304), chỉ tải ảnh chưa có, kiểm tra sha256, lưu `user://catalog/icons`, tối đa 3 tải song song và tạm dừng khi đang đánh. Chưa có ảnh/offline thì dùng ảnh có sẵn trong game.                                                |
| Ví                     | `wallets` + `wallet_ledger` (append-only, `reference` duy nhất chống trùng khi retry). Tài khoản mới nhận 5.000 vàng, 100 KC và 4 vật phẩm khởi đầu (ghi sổ “Quà tân thủ”). Mua vật phẩm `POST /v1/shop/purchase` do server tính giá (ưu đãi nếu rẻ hơn).                                                                         |
| Nạp                    | `GET /v1/topup/packs`, `POST /v1/topup`: gói KC có giá niêm yết VND và gói đổi KC → vàng. **Sandbox**: không có cổng thanh toán, không thu tiền, ghi rõ trong sổ.                                                                                                                                                                 |
| Online                 | `accounts.last_seen_at` cập nhật (tối đa 30 giây/lần) khi client gọi API; client ping `/v1/me` mỗi 45 giây. Online = hoạt động trong 2 phút.                                                                                                                                                                                      |
| Phòng / trận online    | Arena gửi sự kiện phòng (chờ/đang chơi/đóng) và kết quả mỗi vòng tới `POST /internal/v1/arena/events` bằng token dịch vụ (`iss=suni-arena`, `aud=suni-ingest`), không chặn tick, retry 3 lần; idempotent theo (phòng, vòng). Chỉ số: thứ hạng, hạ gục (tính cho chủ bom), số bom, thời gian sống. Snapshot/protocol v1 không đổi. |
| Phòng / trận luyện tập | App PC (đã đăng nhập) báo phòng và kết quả trận bot qua `/v1/practice/rooms`. Do client báo cáo nên lưu `verified=false`, server chỉ tin `account_id` trong token, không phát thưởng.                                                                                                                                             |

Trang Người chơi có trạng thái Hoạt động / Đã khóa / Đã mở khóa (đổi ngay trong danh sách),
online, vàng, KC, số vật phẩm; chi tiết có tab Thông tin (sửa tên, email, VIP), Tài sản
(cộng/trừ tiền có lý do, tặng/thu hồi), Giao dịch, Trận đấu. Trang Phòng & trận có tổng
phòng, phòng chờ/đang diễn ra, người tạo nhiều nhất và lịch sử trận theo người chơi.
Trang Giao dịch liệt kê toàn bộ sổ ví với bộ lọc và tổng nạp sandbox.

Nhập ảnh có sẵn của game vào server (một lần):

```bash
docker cp apps/practice/assets/. suni-bomb-arena-api-1:/tmp/game-assets
docker compose exec api python -m app.admin_cli import-icons /tmp/game-assets
docker compose up -d --force-recreate --no-deps api   # xóa thư mục tạm
```

## Vận hành

```bash
docker compose exec -T postgres psql -U suni -d suni < infra/postgres/004_admin.sql
docker compose exec -T postgres psql -U suni -d suni < infra/postgres/005_sync.sql
docker compose up -d --build --wait api web
docker compose exec api python -m app.admin_cli create <tên> --role owner
docker compose exec api python -m app.admin_cli reset-password <tên>
```

Không có admin mặc định. Nên đặt `/admin` sau Cloudflare Access và bật MFA cho
mọi owner/operator. Giới hạn đăng nhập theo IP hiện gộp chung vì nginx không tin
`X-Forwarded-For`, nên một người thử sai nhiều có thể làm admin khác phải chờ 5 phút.

## Kiểm thử

```bash
cd apps/api && uv run pytest tests/test_admin.py
cd apps/admin && npm ci && npm run typecheck && npm run build
SUNI_WEB_URL=https://boom.sunifactory.com SUNI_ADMIN_USER=<tên> SUNI_ADMIN_PASSWORD=<mật khẩu> \
  npx playwright test -c apps/web/playwright.config.mjs admin.spec.mjs
```

Test trình duyệt chỉ đọc: đăng nhập sai/đúng, mở 11 trang, chi tiết người chơi,
kiểm tra không lỗi console/CSP và không tràn ngang ở 390px.

Bản đồ do admin thêm: xem [MAPS.md](MAPS.md) (template, kiểm tra, phát hành).

Nhiệm vụ và sự kiện LiveOps: xem [LIVEOPS.md](LIVEOPS.md).
Bảng xếp hạng (xem, ẩn người chơi, chỉnh cách tính điểm): xem [LEADERBOARD.md](LEADERBOARD.md).
Hộp thư (gửi thông báo, quà tới người chơi hoặc toàn server): xem [MAIL.md](MAIL.md).
Match EXP (rule EXP PvP/Boss, nhân EXP, chống farm, level curve, thống kê): xem [PROGRESSION.md](PROGRESSION.md).
