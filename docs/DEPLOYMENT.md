# Triển khai Ubuntu

## Cài môi trường

Ubuntu 24.04 LTS x86_64, tối thiểu 2 CPU/2 GB RAM để thử nghiệm.
Theo [Docker chính thức](https://docs.docker.com/engine/install/ubuntu/):

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git openssl unzip
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo docker compose version
```

Các lệnh dưới giả sử user có quyền Docker; nếu chưa, thêm `sudo`.

## Khởi chạy

```bash
git clone https://github.com/huynhcntt2012/codexserver.git
cd codexserver
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
openssl rand -hex 32
# Điền hai giá trị khác nhau vào POSTGRES_PASSWORD và JWT_SECRET trong .env.
docker compose up -d --build --wait
curl --fail http://127.0.0.1:8000/health
curl --fail http://127.0.0.1:2567/health
docker compose ps
```

Password DB dùng hex để ghép URI. Không dùng placeholder hoặc commit `.env`.
DB/Redis chỉ mở trong network Docker. API/arena bind loopback.
`001_initial.sql` chạy **chỉ lần đầu** tạo volume PostgreSQL.

Máy chơi từ xa: mở tunnel trên từng máy chơi:

```bash
ssh -N -L 8000:127.0.0.1:8000 -L 2567:127.0.0.1:2567 user@ubuntu-host
```

Client giữ URL `http://127.0.0.1:8000` và `http://127.0.0.1:2567`.
LAN tin cậy: đặt `BIND_ADDRESS=0.0.0.0`, giới hạn firewall theo mạng LAN.
Internet cần HTTPS/WSS, ví dụ Caddy trên host:

```caddyfile
api.example.com {
    reverse_proxy 127.0.0.1:8000
}
arena.example.com {
    reverse_proxy 127.0.0.1:2567
}
```

Trỏ DNS tới host, mở 80/443, giữ 8000/2567 loopback. Client nhập
`https://api.example.com`, `https://arena.example.com`; tự đổi sang `wss`.
Rate limit hiện gộp theo IP proxy; bổ sung trusted proxy/limiter ở edge khi tăng tải.
Không mở DB/Redis ra Internet.

## Xác nhận

```bash
bash scripts/install-godot.sh /tmp/suni-godot
/tmp/suni-godot/godot --headless --path apps/client --script res://tests/smoke.gd
```

Cần có `GODOT_MULTIPLAYER_SMOKE_OK`: hai guest, cùng phòng, di chuyển, đặt bom, winner.
Endpoint khác dùng `SUNI_API_URL` và `SUNI_ARENA_URL`. Chạy smoke trên staging riêng,
không có người khác trong lobby. Thử tay với hai cửa sổ Godot, Join → Ready;
thử 8 cửa sổ trước khi Ready. Người thứ 9 được matchmaking đưa sang phòng khác.

## Backup, update, rollback

```bash
mkdir -p /tmp/suni-backups
docker compose exec -T postgres pg_dump -U suni -d suni -Fc > /tmp/suni-backups/suni.dump
git pull --ff-only
docker compose up -d --build --wait
docker compose logs --tail=100 api arena
```

Copy backup ra storage khác; kiểm tra restore định kỳ vào DB staging trống bằng
`pg_restore -U suni -d suni` qua `docker compose exec -T postgres`.
Thay password `.env` không tự thay password role trong DB hiện có.
Deploy ngắt trận đang chơi; báo lịch bảo trì. Chưa có drain/rolling deploy.
Migration tiếp theo là file mới, có backup/rollback; sửa baseline không cập nhật volume cũ.
Rollback code bằng checkout commit trước ở thư mục riêng rồi rebuild; rollback DB
cần migration hoặc backup tương ứng. `docker compose down` giữ dữ liệu;
`docker compose down -v` **xóa volume**, chỉ dành cho test dùng một lần.

## CI/CD

Push/PR: format, lint, unit/network/API tests, Docker builds, Godot parse/runtime,
smoke hai client, export `.pck` và notices artifacts. PR không publish image.
Workflow **Build release images** chạy thủ công, chạy lại test rồi publish tag SHA
tới `ghcr.io/<owner>/suni-api:<sha>` và `ghcr.io/<owner>/suni-arena:<sha>`.
Tạo environment `release`, bật required reviewers nếu muốn duyệt phát hành.
Chỉ release commit đã CI xanh. Host cần quyền pull registry:

```bash
# Đặt API_IMAGE và ARENA_IMAGE với cùng SHA trong .env.
docker compose pull api arena
docker compose up -d --no-build --wait
```

Chưa cấu hình host production hoặc SSH secret. Promotion lên Ubuntu là thủ công;
rollback bằng cách đổi cả hai image về SHA đã xác minh trước. Lưu notices và digest mỗi release.
