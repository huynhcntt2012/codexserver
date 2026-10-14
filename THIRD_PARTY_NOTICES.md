# Copyright và dependency

Mã, bản đồ Neon Garden và hình khối nhân vật Pilot được tạo riêng trong repository,
Copyright (c) 2026 Suni Bomb Arena contributors, theo [MIT](LICENSE).
Không có nhạc, sprite, logo, source hoặc nhân vật từ Boom Online. Chưa nhập asset bên ngoài.

Giữ notices của từng dependency khi phân phối. License dự án không thay thế license bên thứ ba.
Phiên bản chính xác nằm trong `package-lock.json`, `apps/api/uv.lock` và image tags trong Compose.

| Thành phần | License / nguồn chính thức |
| --- | --- |
| Godot 4.4.1 | [MIT, Juan Linietsky, Ariel Manzur và Godot contributors](https://github.com/godotengine/godot/blob/4.4.1-stable/LICENSE.txt) |
| Thư viện và font đi kèm Godot | [Copyright và notices đầy đủ](https://github.com/godotengine/godot/blob/4.4.1-stable/COPYRIGHT.txt); giữ nguyên khi phân phối engine |
| Colyseus core / transport | [MIT, Endel Dreyer](https://github.com/colyseus/colyseus/blob/master/LICENSE) |
| Express, express-rate-limit, ws, jose | MIT; notices được thu thập trực tiếp từ gói đã khóa |
| Marked 18.1.1 | [MIT, MarkedJS (2018+) và Christopher Jeffrey (2011–2018)](https://github.com/markedjs/marked/blob/v18.1.1/LICENSE); kèm notice Markdown BSD của John Gruber (2004). Render tài liệu trên server; giữ nguyên toàn bộ LICENSE trong package và gói notices |
| FastAPI, Starlette, SQLAlchemy, pwdlib, PyJWT, redis-py | MIT hoặc BSD; notices chính xác từ metadata gói đã khóa |
| Uvicorn | BSD-3-Clause |
| Psycopg 3 | [LGPL-3.0, kèm ngoại lệ cho OpenSSL](https://www.psycopg.org/psycopg3/docs/basic/install.html#license); giữ thư viện riêng, cho phép thay thế, cung cấp license và nguồn tương ứng khi phân phối image |
| PostgreSQL 16 | [PostgreSQL License](https://www.postgresql.org/about/licence/) |
| Redis 7.2 | [BSD-3-Clause](https://github.com/redis/redis/blob/7.2/COPYING); không tự ý đổi sang nhánh có license khác |
| Node.js / Python / Debian images | Giữ notices của runtime và các gói hệ điều hành trong image |
| Nginx (web proxy) | [BSD-2-Clause, Igor Sysoev và Nginx, Inc.](https://nginx.org/LICENSE); giữ notices trong image và `apps/web/licenses/NGINX_LICENSE.txt` |
| Playwright (chỉ kiểm thử) | Apache-2.0; license từ package `@playwright/test` đã khóa, không gửi xuống trình duyệt người chơi |

## Tạo gói notices

```bash
npm ci
node scripts/collect-node-licenses.mjs
uv run --project apps/api python scripts/collect-python-licenses.py
```

Kết quả nằm trong `build/licenses/` (CI lưu artifact), gồm nguyên văn notices và danh mục
phiên bản. Không coi metadata thiếu hoặc asset công khai là bằng chứng được sử dụng.
Trước khi phát hành, kiểm tra mục `REVIEW REQUIRED`, các gói không có file license,
và thông báo của engine/OS; bổ sung nguồn và notices tương ứng. Asset chưa xác minh
phải thay bằng hình khối tự tạo. Không có dependency nhạc/ảnh trả phí hay thanh toán thật.
