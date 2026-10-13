# Kiểm thử giai đoạn 1

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
