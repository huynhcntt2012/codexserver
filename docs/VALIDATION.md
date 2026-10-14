# Kiểm thử giai đoạn 1

## Trang tài liệu arena — 2026-10-14

- Node 22: lint, build và 13/13 arena tests đạt. Network test kiểm tra thêm
  HTML/CSS công khai, mục lục, liên kết source, hai URL `/documents` và
  `/documents/`, cùng các hành vi WebSocket/gameplay có sẵn.
- Format và whitespace check đạt. Audit dependency production không có cảnh báo;
  notices của Marked 18.1.1 được giữ trong package và bundle Node.
- Docker runtime mới chạy healthy trên stack riêng `suni-room-preview`.
  Web multiplayer smoke và Godot 4.4.1 headless smoke đạt trên stack này.
- Chromium 1440px và 390px: kiểm tra đường dẫn trực tiếp và qua `/arena/` proxy,
  hai dạng URL có/không dấu `/` cuối, CSS, mục lục, cuộn đến section và không
  tràn ngang toàn trang; không có lỗi JavaScript/console.
  Ảnh: [desktop](screenshots/arena-documents.png),
  [mobile](screenshots/arena-documents-mobile.png).
- Đã triển khai riêng arena theo yêu cầu của chủ dự án bằng image
  `suni-arena:documents-20261014`; giữ image cũ `suni-arena:e7bd301` để rollback.
  Chromium xác nhận HTTPS `/documents` và `/documents/` trả 200, tải CSS và mục
  lục đúng; `/health` trả `{"status":"ok"}`. Proxy web local cũng trả trang 200.
- Các kết quả trên là kiểm thử local và xác nhận triển khai, không phải kết quả
  GitHub Actions của commit mới. Không chạy kịch bản tạo tài khoản/trận thử trên
  production trong đợt cập nhật tài liệu này.

## Bản web — 2026-10-14

Chạy local trên stack riêng `suni-web-preview`, website tại loopback cổng 18080,
PostgreSQL/Redis/API/arena riêng. Không kiểm thử trên production.

| Hạng mục                                                        | Kết quả                                                                                   |
| --------------------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Node 22: arena lint, strict TypeScript, build                   | Qua                                                                                       |
| Gameplay + WebSocket arena thật                                 | 13/13 qua                                                                                 |
| Python 3.12: API pytest                                         | 21/21 qua                                                                                 |
| Web adapter: enum, validation, lỗi HTTP, giữ phiên, hủy request | 4/4 qua                                                                                   |
| Web → Nginx → API/arena smoke                                   | Qua: auth, inventory/VIP, 2 client, move/bomb, winner, ván tiếp, rời phòng/đăng xuất      |
| Chromium desktop 1440px + mobile 390px                          | Qua một kịch bản xuyên suốt: form, keyboard/touch, trận 2 người, kết quả, phiên và reload |
| Compose web healthcheck                                         | Qua                                                                                       |

Ảnh giao diện: [trang chủ](screenshots/web-home.png),
[trận đấu](screenshots/web-gameplay.png), [mobile](screenshots/web-mobile.png).
API vẫn có một deprecation warning Starlette/httpx. Kiểm thử Node ban đầu trên
host Node 18 không tương thích; đã chạy lại thành công bằng Node 22.23.3 container.

Đã đổi CI sang kiểm thử web. Kết quả local dưới đây không thay thế GitHub Actions. Chưa đo tải
nhiều phòng, chưa chơi giữa hai thiết bị vật lý, chưa xác nhận Safari/Firefox hoặc
hostname HTTPS production. Giới hạn auth qua proxy vẫn gộp 20 yêu cầu/phút.
Không build/cập nhật gói ứng dụng Linux trong đợt chuyển web.

## Kết quả lịch sử của bản desktop

Đã chạy trong workspace ngày 2026-10-13:

| Hạng mục                                       | Kết quả                                  |
| ---------------------------------------------- | ---------------------------------------- |
| Node 22 container: ESLint + TypeScript strict  | Qua                                      |
| node:test gameplay + WebSocket thật            | 13/13 qua                                |
| TypeScript production build                    | Qua                                      |
| Python 3.12: Ruff lint/format                  | Qua                                      |
| pytest trong Docker test target                | 5/5 qua                                  |
| Godot 4.4.1: import, parse, main scene runtime | Qua                                      |
| Hai adapter Godot → FastAPI → Colyseus         | Auth, join, move, bomb, winner qua       |
| Docker Compose build + healthcheck             | Cả PostgreSQL, Redis, API, arena healthy |
| Godot Linux resource pack                      | Export `.pck` thành công                 |
| npm audit sau nâng dependency                  | 0 cảnh báo tại thời điểm cài             |
| Node/Python dependency notices                 | Tạo được bundle trong `build/licenses`   |

Đã chạy Godot đồ họa qua Xvfb, kết nối hai người chơi thật và lưu ảnh tại
`docs/images/gameplay.png`.

Test mạng xác nhận token giả bị từ chối, tám người cùng phòng, seat thứ chín bị
từ chối khi join trực tiếp, server xử lý di chuyển/bom/thắng, giới hạn HTTP 429 và
payload quá lớn 413. Smoke Godot dùng cùng adapter với client đồ họa.

Test API dùng SQLite cho unit tests; smoke Compose dùng PostgreSQL và Redis thật.
Có một cảnh báo deprecation từ FastAPI/Starlette TestClient về httpx; test vẫn qua.
Chưa đo latency qua WAN hoặc load test nhiều phòng; chưa kiểm thử Windows/macOS,
độc lập export templates, failover DB hoặc production rollout.
GitHub Actions cần được xác nhận trên remote sau khi push; kết quả local không thay thế CI.

## Web: đăng nhập → chọn phòng → sẵn sàng → trận đấu (2026-10-14)

- Trang đăng nhập/đăng ký riêng; chỉ mở danh sách phòng sau xác thực.
- Danh sách phòng thật có mã phòng, số người, số sẵn sàng, tạo phòng và chọn
  đúng phòng. Phòng đầy khóa nút vào; countdown/playing không còn trong danh sách.
- Node 22 trong Docker: lint, 13 arena tests (gồm WebSocket thật), 5 web client
  tests và build đều đạt. Format check và diff whitespace check đạt.
- Stack riêng `suni-room-preview`, web `127.0.0.1:18081`: web multiplayer smoke
  và Godot 4.4.1 headless smoke đạt. Không thay protocol snapshot của Godot.
- Playwright Chromium: desktop 1440px và mobile 390px, đăng ký/sai mật khẩu,
  chặn truy cập màn hình phòng khi chưa đăng nhập, tạo hai phòng riêng, chọn
  đúng phòng, chờ tất cả Ready, keyboard/touch, kết quả, ván sau, rời phòng,
  giữ phiên, đăng xuất và tải lại trang đều đạt; không có lỗi JavaScript.
- Ảnh kiểm thử tại `build/web-screenshots`; ảnh để review trong
  `docs/screenshots/web-*.png`. Chưa triển khai production.

## Kiểm tra lại trước khi push — 2026-10-14

- Node 22.23.3: cài bằng lockfile, lint, 13 arena tests, 5 web tests, build,
  format và kiểm tra whitespace đều đạt. Audit production không có cảnh báo.
- Python 3.12 trong Docker test target: Ruff lint/format và 21 API tests đạt;
  còn một cảnh báo deprecation Starlette/httpx.
- Build lại stack `suni-room-preview` riêng trên loopback; cả năm service healthy.
  Web multiplayer smoke và Playwright Chromium desktop/mobile đều đạt.
- Godot 4.4.1: import/runtime, smoke multiplayer, lobby và account tests đạt.
  Không tạo gói desktop mới.
- Đã tạo bundle notices Node/Python trong `build/licenses` và cập nhật ảnh review
  từ lần kiểm thử trình duyệt này.

## GitHub Actions

Commit `dd0b840` trên nhánh `suni/06-client-polish` đã đạt cả ba job `arena`,
`api` và `web-and-stack`: [lần chạy CI](https://github.com/huynhcntt2012/codexserver/actions/runs/38527697488).
Kết quả gồm build stack sạch và kiểm thử Chromium trên GitHub runner.
