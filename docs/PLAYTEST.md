# Chuẩn bị buổi chơi thử Windows/Linux qua LAN hoặc VPN

## Gói gửi người chơi

Hai ZIP độc lập nằm trong `build/playtest/`, kèm `SHA256SUMS.txt`.
Mỗi ZIP chứa ứng dụng, dữ liệu `.pck`, hướng dẫn tiếng Việt, notices và `BUILD.json`
ghi commit nguồn. Chỉ gửi bản có `dirty: false` sau khi CI đạt.
Hướng dẫn người chơi: [PLAYTEST_PLAYER.md](PLAYTEST_PLAYER.md).

CI upload artifact **desktop-playtest** chứa hai ZIP và checksum. Mở lần chạy CI
của nhánh `dev/codex` trong tab Actions để tải (cần đăng nhập GitHub).
Artifact lưu 14 ngày; tải về rồi gửi ZIP đúng hệ điều hành cho người chơi.
Chưa tạo public release hoặc triển khai server Internet.

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
CI chạy binary Windows trên runner Windows để kiểm tra khởi động.
Các kiểm tra này chưa thay thế buổi chơi thật giữa hai máy qua LAN/VPN.

## Máy chủ buổi chơi thử

Dùng một máy Ubuntu trong LAN/VPN; xem [cài Docker](DEPLOYMENT.md).
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
`.env`. Server chơi thử hiện tại dùng `192.168.1.98`; đặt `BIND_ADDRESS=192.168.1.98`.
IP đó phải tồn tại trên máy và người chơi phải truy cập được; giữ nguyên
`API_PORT=8000`, `ARENA_PORT=2567`. Repo mặc định vẫn bind loopback.

```bash
docker compose up -d --build --wait
docker compose ps
curl --fail http://192.168.1.98:8000/health
curl --fail http://192.168.1.98:2567/health
```

Client đã điền sẵn hai URL trên; có thể sửa trong giao diện hoặc qua biến môi trường
`SUNI_API_URL`/`SUNI_ARENA_URL`. Nếu đổi server, cập nhật IP trong các lệnh.
Cho phép TCP 8000 và 2567 từ đúng
subnet LAN/VPN trên firewall của máy chủ; không mở PostgreSQL/Redis hay forward
port router ra Internet. HTTP chỉ dành cho mạng thử nghiệm tin cậy; nên dùng guest.
Gửi người chơi ZIP, checksum và hai URL: `http://IP:8000`, `http://IP:2567`.
Người chơi trên VPN dùng IP VPN ở cả hai URL, người chơi LAN dùng IP LAN.

## Kiểm tra trước khi mời người chơi

```bash
SUNI_API_URL=http://192.168.1.98:8000 SUNI_ARENA_URL=http://192.168.1.98:2567 \
  /tmp/suni-godot/godot --headless --path apps/client --script res://tests/smoke.gd
```

Chạy trên server thử nghiệm riêng, chưa có người trong lobby. Phải thấy
`GODOT_MULTIPLAYER_SMOKE_OK`. Sau đó mở hai bản game trên hai máy, xác nhận cùng
phòng, Ready, di chuyển, bom, kết quả và bắt đầu ván mới. Thử đóng một client
giữa trận rồi Join lại. Ghi lại commit trong `BUILD.json` cùng kết quả buổi thử.

Kết thúc buổi thử: `docker compose stop` giữ dữ liệu. Khi chỉ kiểm thử trên máy
chủ, đổi `BIND_ADDRESS=127.0.0.1` rồi chạy lại Compose. Không gửi `.env`, database
hay token cùng gói client.
