# Server realtime Colyseus: tính năng và tích hợp

Đọc trực tiếp tại <https://arena.sunifactory.com/documents>, không cần đăng nhập.
Arena phục vụ trang HTML từ chính file này; cập nhật tài liệu cần build và triển
khai lại arena. Local: <http://127.0.0.1:2567/documents>.

Tài liệu mô tả những gì đã có trong `apps/arena`, dành cho dev frontend, gameplay
và backend. Web là client đang phát triển; Godot là client cũ. Cả hai dùng cùng
room `arena` và snapshot version 1. Phiên bản đang khóa trong
[package.json](../apps/arena/package.json): `@colyseus/core` 0.17.52,
`@colyseus/ws-transport` 0.17.13.

## Các tính năng đã có

| Nhóm                          | Hành vi hiện tại                                                                                       | Code chính                                                                     |
| ----------------------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------ |
| Tìm và tạo phòng              | Liệt kê phòng chờ, tạo phòng, vào theo mã hoặc tự tìm/tạo phòng; tối đa 8 người/phòng                  | [server.ts](../apps/arena/src/server.ts), [room.ts](../apps/arena/src/room.ts) |
| Xác thực                      | JWT từ API; tên và account ID lấy từ token đã ký; chặn cùng tài khoản vào hai seat trong một phòng     | [auth.ts](../apps/arena/src/auth.ts), [room.ts](../apps/arena/src/room.ts)     |
| Lobby và vòng đời ván         | Tối thiểu 2 người, tất cả sẵn sàng, đếm ngược 3 giây; kết quả 8 giây rồi về lobby cho ván tiếp         | [game.ts](../apps/arena/src/game.ts)                                           |
| Gameplay do server quyết định | Bản đồ 15×13, di chuyển theo ô, va chạm, đặt bom, phá thùng, nổ dây chuyền, loại người chơi, thắng/hòa | [game.ts](../apps/arena/src/game.ts)                                           |
| Đồng bộ realtime              | Tick 50 ms, gửi toàn bộ snapshot sau mỗi tick (mục tiêu 20 Hz), gửi snapshot ban đầu khi join          | [room.ts](../apps/arena/src/room.ts)                                           |
| Rời phòng/mất kết nối         | Xóa người khỏi mô phỏng; hủy countdown hoặc xét lại người thắng khi đang chơi                          | [room.ts](../apps/arena/src/room.ts), [game.ts](../apps/arena/src/game.ts)     |
| Giới hạn request              | Rate limit HTTP, giới hạn packet/client và kích thước payload; bỏ qua action không hợp lệ              | [server.ts](../apps/arena/src/server.ts), [room.ts](../apps/arena/src/room.ts) |
| Vận hành cơ bản               | Health endpoint, Docker healthcheck, kiểm thử mô phỏng và WebSocket thật                               | [compose.yaml](../compose.yaml), [tests](../apps/arena/tests)                  |

API FastAPI phụ trách đăng ký/đăng nhập/guest, inventory và VIP chỉ đọc.
Arena xác minh JWT bằng secret dùng chung; không truy vấn PostgreSQL hoặc Redis
cho từng tick. Inventory/VIP chưa tác động tới gameplay.

## Phòng và vòng đời trận

```text
waiting → countdown (3 giây) → playing (tối đa 180 giây)
   ↑                              ↓
   └──────── finished (8 giây) ←───┘
```

- Chỉ nhận người mới ở `waiting`. Phòng khóa khi `countdown`, `playing` hoặc
  `finished`; phòng đủ 8 người cũng không thể join. Server kiểm tra lại lúc join
  để xử lý trường hợp phòng vừa chuyển trạng thái sau khi client lấy danh sách.
- `ready` chỉ đặt sẵn sàng thành `true`, chưa có thao tác bỏ sẵn sàng.
  Một người có thể ready nhưng chưa bắt đầu được ván.
- Rời phòng khi countdown đưa phòng về `waiting`, xóa ready của người còn lại.
  Khi đang chơi, người rời bị xóa ngay; bom đã đặt vẫn tồn tại. Nếu còn tối đa
  một người sống, server kết thúc ván ngay.
- Người chết còn kết nối tiếp tục nhận snapshot tới hết ván nhưng không thể
  di chuyển/đặt bom. Chưa có chế độ spectator cho người ngoài vào xem.
- Sau kết quả, reset bản đồ, bom/lửa, vị trí spawn, trạng thái sống và ready;
  tăng `round`. Người còn trong phòng cần ready lại.
- Mất kết nối không được giữ chỗ hoặc khôi phục nhân vật. Join lại tạo seat mới.

## Luật gameplay đang chạy

| Thành phần | Quy tắc                                                                                          |
| ---------- | ------------------------------------------------------------------------------------------------ |
| Bản đồ     | Layout cố định, nguyên bản 15×13; 8 vị trí spawn; tạo lại cùng layout mỗi ván                    |
| Di chuyển  | 4 hướng, tối đa 1 ô/150 ms; tường, thùng, bom và người sống chặn đường                           |
| Input      | Một action đang chờ/người/tick; `bomb` ưu tiên movement; không có hàng đợi nhiều bước            |
| Bom        | Tối đa 1 bom đang tồn tại/người; đặt tại ô server ghi nhận; ngòi 2 giây                          |
| Tia nổ     | Ô đặt bom và tối đa 2 ô theo mỗi hướng; tường chặn; thùng bị phá và chặn phần tia còn lại        |
| Dây chuyền | Gặp bom thì kích nổ ngay và dừng tia đó; xóa bom trước khi xử lý dây chuyền để tránh vòng lặp    |
| Lửa        | Tồn tại 500 ms trong lúc mô phỏng trận; đứng trên hoặc đi vào lửa đều bị loại                    |
| Kết quả    | Người sống cuối thắng; không còn ai sống là hòa; nếu trận vẫn tiếp diễn khi hết 180 giây thì hòa |

Chủ bom có thể rời ô vừa đặt nhưng không đi ngược qua bom. Server xử lý bom đến
hạn và lửa trước movement, kiểm tra lửa lại sau movement, rồi mới chọn winner.
Các vụ nổ trong cùng tick được xử lý trước khi xét thắng nên có thể chết đồng
thời. Bom đến hạn được duyệt theo thứ tự đặt; thùng vừa bị phá có thể cho tia nổ
xử lý sau trong cùng tick đi qua.

Thời gian mô phỏng tăng 50 ms mỗi tick, không lấy thời gian do client cung cấp.
Khi host chậm, mô phỏng có thể chậm theo. Client chỉ gửi ý định, không gửi vị trí,
timer, damage, tốc độ hoặc kết quả trận.

## HTTP và luồng kết nối

Đường dẫn bên dưới là trực tiếp tới arena (local mặc định qua Compose:
`http://127.0.0.1:2567`). Khi đi qua website, thêm prefix `/arena`, ví dụ
`/arena/rooms`; xem cấu hình proxy tại [WEB.md](WEB.md).

| Method và endpoint                   | Xác thực/body                        | Kết quả                                                                     |
| ------------------------------------ | ------------------------------------ | --------------------------------------------------------------------------- |
| `GET /health`                        | Không cần token                      | `{ "status": "ok" }`; kiểm tra HTTP arena, không kiểm tra DB/Redis          |
| `GET /documents`                     | Không cần token                      | Trang tài liệu HTML, có mục lục; hỗ trợ cả `/documents/`                    |
| `GET /rooms`                         | Header `Authorization: Bearer <JWT>` | `{ "rooms": [{ "roomId", "players", "maxPlayers", "ready", "joinable" }] }` |
| `POST /matchmake/create/arena`       | JSON `{ "token": "<JWT>" }`          | Tạo phòng và đặt chỗ                                                        |
| `POST /matchmake/joinById/{roomId}`  | JSON `{ "token": "<JWT>" }`          | Đặt chỗ trong phòng đã chọn                                                 |
| `POST /matchmake/joinOrCreate/arena` | JSON `{ "token": "<JWT>" }`          | Tìm phòng có thể join hoặc tạo phòng mới                                    |

Danh sách chỉ gồm phòng công khai trong process hiện tại, đang `waiting` và có
người. Phòng đầy vẫn hiện với `joinable: false`. `players` là số người trong mô
phỏng, `ready` là số người sẵn sàng, `maxPlayers` là 8. Không trả danh tính người
chơi; có header `Cache-Control: no-store`. Danh sách có thể thay đổi trước lúc
join; client cần xử lý lỗi và tải lại. Web hiện polling mỗi 5 giây, chưa có push
sự kiện danh sách phòng.

Luồng tích hợp:

1. Gọi API `/v1/register`, `/v1/login` hoặc `/v1/guests` để lấy `access_token`.
   Qua website dùng prefix `/api`. Token API hiện có hạn một giờ.
2. Gọi một endpoint matchmaking với `Content-Type: application/json` và body
   chứa token. Response seat có các trường `sessionId`, `roomId`, `processId`
   ở cấp đầu tiên.
3. Mở `ws(s)://host/{processId}/{roomId}?sessionId=...`. Qua website dùng
   `ws(s)://host/arena/{processId}/{roomId}?sessionId=...`.
4. Arena xác thực trong WebSocket handshake. HTTP đặt chỗ thành công **chưa có
   nghĩa** JWT được chấp nhận. Nhận `JOIN_ROOM` (10) rồi gửi ACK `[10]`.
5. Nhận snapshot, gửi action theo định dạng dưới đây. Gửi `[12]` để rời phòng.

Adapter có sẵn: [web network.mjs](../apps/web/public/network.mjs) và
[Godot network.gd](../apps/client/scripts/network.gd). Đây là adapter cho wire
protocol hiện tại, không phải SDK Colyseus tổng quát.

## Message và snapshot version 1

WebSocket dùng binary frame. Serializer là `none`, đã tắt Schema patches;
không gửi action dưới dạng JSON text thuần.

| Chiều           | Định dạng                          | Nội dung                                                           |
| --------------- | ---------------------------------- | ------------------------------------------------------------------ |
| Client → server | `[13, 0, 0xa0 + length, ...ASCII]` | `ROOM_DATA` (13), message type số `0`, MsgPack fixstr chứa action  |
| Server → client | `[17, 1, ...UTF8_JSON]`            | `ROOM_DATA_BYTES` (17), message type số `1`, toàn bộ snapshot JSON |
| Client → server | `[12]`                             | `LEAVE_ROOM`                                                       |

Action hợp lệ: `up`, `down`, `left`, `right`, `bomb`, `ready`.
Ví dụ `bomb` là `[13, 0, 164, 98, 111, 109, 98]`. Server lấy danh tính từ
`client.sessionId`, không nhận ID người chơi trong payload. Action lạ, object
giả trạng thái hoặc action sai phase bị bỏ qua, không có ACK cho từng input.

| Trường snapshot   | Kiểu / ý nghĩa                                                                |
| ----------------- | ----------------------------------------------------------------------------- |
| `version`         | `1`                                                                           |
| `width`, `height` | `15`, `13`                                                                    |
| `phase`           | `waiting`, `countdown`, `playing`, `finished`                                 |
| `now`             | Số ms mô phỏng tính từ lúc tạo `Arena`, không phải Unix timestamp             |
| `deadline`        | Mốc theo cùng đồng hồ `now`: hết countdown/trận/kết quả; bỏ qua khi `waiting` |
| `winner`          | Session ID người thắng; khi `finished`, `null` nghĩa là hòa                   |
| `round`           | Bắt đầu từ 1, tăng sau mỗi lần reset                                          |
| `grid`            | Mảng hàng `grid[y][x]`, `0` = sàn, `1` = tường, `2` = thùng                   |
| `players`         | Mảng `{ id, name, slot, x, y, alive, ready }`                                 |
| `bombs`           | Mảng `{ id, owner, x, y, explodeAt }`                                         |
| `flames`          | Mảng `{ x, y, expiresAt }`                                                    |

Tọa độ ô bắt đầu từ 0; `x` tăng sang phải, `y` tăng xuống dưới. `players[].id`
và `bombs[].owner` là session ID, không phải account ID. `slot` thuộc 0–7;
`name` lấy từ JWT và cắt tối đa 24 ký tự. ID bom là số. `explodeAt`/`expiresAt`
cùng đơn vị và đồng hồ với `now`. Chỉ đọc winner như kết quả khi `finished`;
`null` ở các phase khác không có nghĩa ván đã hòa. Khi `finished`, bom/lửa còn
lại được giữ trong snapshot tới reset, không tiếp tục mô phỏng gameplay.

## Xác thực, giới hạn và lỗi cần xử lý

- Bắt buộc `JWT_SECRET` tối thiểu 32 ký tự, giống API. JWT phải dùng HS256,
  issuer `suni-api`, audience `suni-arena`, có `sub` và `name` dạng chuỗi,
  có `exp` hợp lệ. Token đầu vào giới hạn 4096 ký tự.
- Token được kiểm tra khi vào phòng và mỗi lần gọi `/rooms`; chưa kiểm tra lại
  định kỳ để đá người đang chơi khi token hết hạn. Chưa có revoke/refresh token.
- Một account chỉ có một seat trong cùng phòng; chưa chặn account ở nhiều phòng.
- `/matchmake`: 30 request/IP/phút; `/rooms`: 120 request/IP/phút, hai bộ đếm
  riêng. JSON HTTP giới hạn 8 KB, WebSocket payload tối đa 1024 byte,
  `maxMessagesPerSecond = 40` mỗi client.
- Sau reverse proxy, giới hạn hiện gộp theo IP proxy; server chưa tin
  `X-Forwarded-For`. Không ghi token/password/sessionId vào log.

| Trường hợp                                             | Kết quả cần xử lý                                                      |
| ------------------------------------------------------ | ---------------------------------------------------------------------- |
| `/rooms` thiếu/sai/hết hạn token                       | HTTP 401, `{ "error": "Invalid access token" }`                        |
| Lỗi truy vấn danh sách phòng                           | HTTP 503, `{ "error": "Room list unavailable" }`                       |
| Quá giới hạn HTTP                                      | HTTP 429                                                               |
| JSON body quá lớn                                      | HTTP 413                                                               |
| JWT bị từ chối khi vào room                            | Colyseus `ERROR` (11), mã lỗi 401 rồi ngắt kết nối                     |
| Account trùng trong room hoặc ván vừa bắt đầu lúc join | Lỗi join mã 409 (`Account already in room` / `Round already starting`) |
| Matchmaking vào phòng đầy/khóa/không tồn tại           | HTTP lỗi từ Colyseus; làm mới danh sách và chọn lại                    |

## Phạm vi chưa có

- Reconnect/resume, giữ chỗ khi mất mạng, vào giữa trận, chế độ xem riêng.
- Chat, đội, phòng có mật khẩu, quyền chủ phòng/kick hoặc tùy chỉnh luật/map.
- Power-up, tăng số bom/tầm nổ, gameplay theo inventory/VIP, bot.
- Xếp hạng, matchmaking theo kỹ năng, lịch sử kết quả lưu DB, replay.
- Đồng bộ state bằng delta/Schema, ACK/sequence cho input, lag compensation.
- Lưu/khôi phục trận khi restart, shared presence/matchmaking cho nhiều replica.

Trạng thái trận nằm trong RAM của một process. Redis hiện phục vụ rate limit
auth của API, không lưu trận. Restart arena ngắt các trận đang chơi. Chưa thể
chạy nhiều replica arena với cấu hình hiện tại; danh sách phòng cũng chỉ đọc
room local.

## Chạy và kiểm chứng

Cách chạy cả stack, tạo `.env` và cấu hình secret: [README](../README.md#chạy-nhanh-trên-ubuntu).
Compose mặc định chỉ publish arena ra `127.0.0.1:2567`. Khi chạy trực tiếp bằng
`npm run dev`, `PORT` mặc định là 2567 nhưng process bind `0.0.0.0`;
`BIND_ADDRESS` trong `.env` chỉ điều khiển port publish của Compose.

Từ thư mục gốc, dùng Node 22.13+:

```bash
npm ci
npm run lint
npm test
npm run build
npm run format:check
```

| Kiểm thử có sẵn                                        | Phạm vi                                                                                                                                                     |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [game.test.ts](../apps/arena/tests/game.test.ts)       | Spawn/capacity, ready/countdown, từ chối input giả, va chạm, chống spam di chuyển/bom, ngòi/lửa, dây chuyền, chết đồng thời, thắng/hòa, disconnect và reset |
| [network.test.ts](../apps/arena/tests/network.test.ts) | Server và WebSocket thật với 8 client; JWT giả, account trùng, phòng đầy/khóa, danh sách phòng, movement/bomb/kết quả, HTTP 413 và matchmaking 429          |
| [Kiểm thử web](WEB.md#kiểm-thử)                        | Adapter/frontend và smoke/browser test với stack thật; đăng nhập, chọn phòng và trận nhiều người                                                            |
| [Godot smoke](../apps/client/tests/smoke.gd)           | Adapter Godot cũ qua stack thật; bắt buộc cùng network test khi nâng protocol/dependency Colyseus                                                           |

`npm test` chạy mô phỏng và network test; network test tự khởi động arena trên
loopback và tự ký JWT thử nghiệm, không cần API/PostgreSQL/Redis. Smoke web/Godot
cần stack thử nghiệm riêng. Danh sách trên mô tả coverage có sẵn, không thay thế
kết quả chạy kiểm thử của từng commit. Kiến trúc tổng thể: [ARCHITECTURE.md](ARCHITECTURE.md).
