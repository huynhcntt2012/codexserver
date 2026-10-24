# Suni Bomb Arena trên trình duyệt

## Chạy local

Chuẩn bị `.env` theo README, giữ `BIND_ADDRESS=127.0.0.1` và đặt `WEB_PORT=8081`.

```bash
docker compose up -d --build --wait
docker compose ps
```

Mở <http://127.0.0.1:8081/demo/> (trang gốc `/` là website quảng bá, xem
[PORTAL.md](PORTAL.md)).

`/demo/` chạy **chính bản build của app PC** (`apps/practice`, Godot xuất Web tại
`/practice/engine/`): màn đăng nhập, sảnh PC, cửa hàng, trang bị, nhiệm vụ, xếp hạng,
hộp thư, cài đặt, phòng online, luyện tập với bot, Đại Chiến Boss, EXP và level. Cùng
code và hình với app PC, nên tính năng mới của PC có trên web sau khi build lại:

```bash
GODOT=/path/to/godot python3 scripts/build-practice.py --web-only
docker compose up -d --build --wait web
```

API và arena đi qua proxy cùng hostname (`/api/`, `/arena/`). Nút Thoát trên web quay
về trang chủ. `/practice/` cũ chuyển hướng tới `/demo/`.

Client trình duyệt viết tay trước đây (chỉ phòng online) chuyển sang `/classic/`; các mục
dưới đây mô tả client đó. Trang `#login` dành cho đăng nhập, `#register`
dành cho đăng ký. Đăng ký thành công tự đăng nhập. Sau xác thực, trang `#rooms`
hiển thị danh sách phòng chờ thật: mã phòng, số người (tối đa 8), số người sẵn sàng
và nút **Vào phòng**. Danh sách tự làm mới mỗi 5 giây; có nút **Làm mới** và
**Tạo phòng mới**. Phòng đầy vẫn hiển thị nhưng không thể chọn; phòng đã bắt đầu
không xuất hiện. Nếu phòng vừa đầy/đóng/bắt đầu, chọn lại từ danh sách.

Dùng hai tài khoản ở hai tab, tạo phòng tại tab đầu rồi chọn đúng mã phòng ở tab
còn lại. Trang `#lobby` chỉ hiện danh sách người chơi và trạng thái sẵn sàng.
Bấm **Sẵn sàng** ở cả hai tab: server đếm ngược 3 giây rồi chuyển sang `#game`.
Kết thúc ván, sau 8 giây tự về phòng chờ; **Rời phòng** trở về danh sách phòng.
Truy cập trực tiếp các trang phòng khi chưa đăng nhập sẽ trở về trang đăng nhập.
WASD/mũi tên di chuyển,
Space đặt bom, R sẵn sàng. Trên điện thoại dùng các nút điều hướng và đặt bom.

Tài khoản dùng chung backend với client cũ. Phiên chỉ nằm trong bộ nhớ tab;
rời phòng giữ phiên để vào lại, đăng xuất hoặc tải lại trang sẽ xóa phiên ở client.
Không lưu token hay mật khẩu trong localStorage, sessionStorage hoặc cookie.
Mất mạng giữa trận bị loại; quay lại danh sách để chọn phòng khác.

Frontend là HTML/CSS/JavaScript module, không cần bundler, CDN hoặc font bên ngoài.
Đồ họa Canvas vẽ nguyên bản. Server quyết định tọa độ, bom và kết quả.

## API và WebSocket

Nginx phục vụ tài nguyên web và chuyển tiếp các đường dẫn:

| Đường dẫn trình duyệt                                                 | Dịch vụ nội bộ                           |
| --------------------------------------------------------------------- | ---------------------------------------- |
| `/api/v1/guests`, `/api/v1/register`, `/api/v1/login`                 | FastAPI `api:8000/v1/…`                  |
| `/api/v1/me`, `/api/v1/inventory`, `/api/v1/vip`                      | FastAPI, xác thực Bearer JWT             |
| `/arena/rooms`                                                        | Danh sách phòng chờ, xác thực Bearer JWT |
| `/arena/matchmake/create/arena`, `/arena/matchmake/joinById/{roomId}` | Colyseus `arena:2567/matchmake/…`        |
| `/arena/{processId}/{roomId}?sessionId=…`                             | Colyseus WebSocket                       |

Adapter giữ protocol version 1 giống Godot: chỉ gửi enum ý định, nhận snapshot
20 Hz. Không thay schema API hoặc luật gameplay. Proxy tắt access log để tránh
ghi sessionId; không tin IP do client tự khai báo. Giới hạn auth vẫn gộp theo IP
proxy (20 yêu cầu/phút); trước buổi thử đông người cần thiết kế trusted proxy và
rate limit theo người dùng/IP đã xác thực. Không tăng limit mặc định để né kiểm tra.

## Kiểm thử

Cần Node 22.13+, backend thử nghiệm riêng và Chromium của Playwright.
Các smoke/browser tests tạo tài khoản ngẫu nhiên và chơi trận thật; không chạy
trên server production hoặc phòng đang có người chơi.

```bash
npm ci
npm run test:web
npm run test:web:smoke
npx playwright install --with-deps --only-shell chromium
npx playwright test --config apps/web/playwright.config.mjs
```

Đặt `SUNI_WEB_URL` nếu web không ở cổng 8081. Test trình duyệt kiểm tra desktop
1440px và mobile 390px, form tài khoản, trận hai người, keyboard/touch, kết quả,
ván tiếp theo và phiên đăng nhập. Ảnh nằm trong `build/web-screenshots`, trace khi
lỗi ở `build/web-test-results`. `SUNI_CAPTURE_DIR` đổi nơi lưu ảnh.

Stack kiểm thử riêng, dùng các image đã build:

```bash
WEB_PORT=18081 API_PORT=18000 ARENA_PORT=12567 \
  docker compose -p suni-web-preview up -d --no-build --wait
SUNI_WEB_URL=http://127.0.0.1:18081 npm run test:web:smoke
SUNI_WEB_URL=http://127.0.0.1:18081 \
  npx playwright test --config apps/web/playwright.config.mjs
```

## Website kiểm tra qua Internet

Website quảng bá: <https://boom.sunifactory.com>, chơi trên web (bản PC): <https://boom.sunifactory.com/demo/>,
client cũ: `/classic/`. Tunnel/reverse proxy trỏ tới dịch vụ web
ở `127.0.0.1:8081`, chuyển tiếp API và WebSocket cùng hostname. Người chơi chỉ cần
một URL website; API/PostgreSQL/Redis không cần công khai thêm cổng.

Cập nhật thủ công theo yêu cầu của chủ dự án, sau khi kiểm thử trên stack riêng
và CI đạt. Giữ image trước đó để rollback; chỉ thay web/arena nếu API và database
không đổi. Khởi động lại arena sẽ ngắt các trận đang chơi.

Không đặt JWT secret vào frontend. Không tự động merge hoặc deploy production.
CI hiện kiểm thử web và lưu bằng chứng, không tạo ZIP Linux/Windows.
