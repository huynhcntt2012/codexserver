# Chuẩn bị buổi chơi thử Windows/Linux

> Tài liệu bản desktop cũ. Từ 2026-10-14, ưu tiên [bản web](WEB.md),
> dừng cập nhật Linux và không còn tạo artifact desktop tự động trong CI.

## Gói gửi người chơi

Hai ZIP độc lập nằm trong `build/playtest/`, kèm `SHA256SUMS.txt`.
Mỗi ZIP chứa ứng dụng, dữ liệu `.pck`, hướng dẫn tiếng Việt, notices và `BUILD.json`
ghi commit nguồn và trạng thái thay đổi chưa commit. Bản phát hành dùng `dirty: false`
sau khi CI đạt; bản thử từ workspace có thể có `dirty: true` và cần ghi rõ khi gửi.
Hướng dẫn người chơi: [PLAYTEST_PLAYER.md](PLAYTEST_PLAYER.md).

Các lần chạy CI desktop cũ từng lưu artifact **desktop-playtest** chứa hai ZIP
và checksum trong 14 ngày. CI hiện tại chỉ kiểm thử web; muốn tạo lại ZIP desktop,
build thủ công theo hướng dẫn bên dưới.
Chưa tạo public release. Client mặc định dùng hai subdomain Cloudflare Tunnel bên dưới.

## Máy chủ Internet qua Cloudflare Tunnel

Client điền sẵn `https://api.sunifactory.com` và `https://arena.sunifactory.com`.
Tunnel chuyển API tới HTTP cổng 8000, arena tới HTTP cổng 2567; kết nối trận đấu
dùng WebSocket qua cùng hostname arena. Origin phải là địa chỉ mà process
`cloudflared` truy cập được (loopback nếu cùng host, địa chỉ LAN hoặc tên service
Docker nếu ở môi trường khác). Không cần public trực tiếp hai cổng origin.

Với `cloudflared` chạy trực tiếp trên cùng host, đặt origin API là
`http://127.0.0.1:8000`, arena là `http://127.0.0.1:2567` và giữ
`BIND_ADDRESS=127.0.0.1` trong `.env`.

```bash
curl --fail https://api.sunifactory.com/health
curl --fail https://arena.sunifactory.com/health
```

HTTP 502 nghĩa là chưa kết nối được origin; kiểm tra service URL của tunnel và
trạng thái API/arena trước khi mời người chơi. Có thể sửa URL trong giao diện hoặc
qua `SUNI_API_URL` / `SUNI_ARENA_URL` để dùng máy chủ riêng.

## Build lại trên Ubuntu

Cần Python 3, curl, unzip, sha512sum và Godot 4.4.1. Export templates chính thức
khoảng 1,2 GB, được kiểm tra SHA-512 đã khóa trong script; chỉ trích xuất hai
template desktop cần thiết vào `build/godot-data`.

```bash
bash scripts/install-godot.sh /tmp/suni-godot
bash scripts/install-godot-templates.sh
GODOT=/tmp/suni-godot/godot python3 scripts/build-playtest.py
cd build/playtest
sha256sum --check SHA256SUMS.txt
```

Script dùng [Godot command-line export](https://docs.godotengine.org/en/4.4/tutorials/editor/command_line_tutorial.html),
chạy thử binary Linux ở chế độ headless và đóng gói license cùng hướng dẫn.
CI desktop cũ chạy binary Windows trên runner Windows để kiểm tra khởi động.
Các kiểm tra này chưa thay thế buổi chơi thật giữa hai máy qua LAN/VPN.

## Khởi chạy máy chủ buổi chơi thử

Dùng một máy Ubuntu; xem [cài Docker](DEPLOYMENT.md).
Checkout nhánh chứa cả ứng dụng, vì `main` hiện mới có quy ước repository:

```bash
git clone --branch dev/codex https://github.com/huynhcntt2012/codexserver.git
cd codexserver
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
openssl rand -hex 32
```

Điền hai chuỗi vừa tạo lần lượt vào `POSTGRES_PASSWORD` và `JWT_SECRET` trong
`.env`. Giữ `BIND_ADDRESS=127.0.0.1`, `API_PORT=8000`, `ARENA_PORT=2567`.
API/arena chỉ nhận kết nối từ máy chủ; người chơi từ xa dùng hai domain HTTPS
qua tunnel.

```bash
docker compose up -d --build --wait
docker compose ps
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:2567/health
```

Nếu muốn chơi trực tiếp qua LAN/VPN thay vì tunnel, đổi `BIND_ADDRESS` sang IP
LAN/VPN của máy chủ, chạy lại Compose và đổi hai URL mặc định trong giao diện hoặc qua biến môi trường
`SUNI_API_URL`/`SUNI_ARENA_URL`. Nếu đổi server, cập nhật IP trong các lệnh.
Cho phép TCP 8000 và 2567 từ đúng
subnet LAN/VPN trên firewall của máy chủ; không mở PostgreSQL/Redis hay forward
port router ra Internet. HTTP chỉ dành cho mạng thử nghiệm tin cậy; nên dùng guest.
Gửi người chơi ZIP, checksum và hai URL: `http://IP:8000`, `http://IP:2567`.
Người chơi trên VPN dùng IP VPN ở cả hai URL, người chơi LAN dùng IP LAN.

## Kiểm tra trước khi mời người chơi

```bash
SUNI_API_URL=https://api.sunifactory.com SUNI_ARENA_URL=https://arena.sunifactory.com \
  /tmp/suni-godot/godot --headless --path apps/client --script res://tests/smoke.gd
```

Chạy trên server thử nghiệm riêng, chưa có người trong lobby. Phải thấy
`GODOT_MULTIPLAYER_SMOKE_OK`. Sau đó mở hai bản game trên hai máy, xác nhận cùng
phòng, Ready, di chuyển, bom, kết quả và bắt đầu ván mới. Thử đóng một client
giữa trận rồi Join lại. Ghi lại commit trong `BUILD.json` cùng kết quả buổi thử.

Kết thúc buổi thử: `docker compose stop` giữ dữ liệu. Khi chỉ kiểm thử trên máy
chủ, đổi `BIND_ADDRESS=127.0.0.1` rồi chạy lại Compose. Không gửi `.env`, database
hay token cùng gói client.
