# Copyright và dependency

Mã, bản đồ Neon Garden và hình khối nhân vật Pilot được tạo riêng trong repository,
Copyright (c) 2026 Suni Bomb Arena contributors, theo [MIT](LICENSE).
Không có nhạc, sprite, logo, source hoặc nhân vật từ Boom Online.

Bộ SVG Bông, Mây, Lá, Nắng trong `apps/web/public/demo/art` và `apps/client/art`
được vẽ bằng mã trong repository theo các ảnh tham chiếu Bụp Bụp do người dùng cung cấp.
Bản nhân vật mới dùng PNG từ hai ZIP do người dùng cung cấp:
`Game_Boom_Godot_Demo.zip` và `Game_Boom_Starter_Assets.zip`.
README nguồn mô tả hình gốc tạo bằng AI, không lấy từ Boom Online. Nhập nguyên trạng
5 sprite sheet, 5 portraits, nền, cỏ, tường, thùng, bom và splash; không nhập mã gameplay offline.
Giữ README nguồn, metadata và SHA-256 tại `art/boom/` của web và PC.
Không tự gán MIT hoặc khẳng định quyền sở hữu độc quyền đối với các PNG này.
Đây là starter art người dùng yêu cầu dùng để verify; README nguồn lưu ý cần rà soát
thêm trước phát hành thương mại. Các SVG cũ vẫn thuộc mã/art ban đầu của repository.

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
| Next.js 16.3.8, React / React DOM 19.3.0 (admin portal) | MIT; chỉ JS đã bundle của Next/React (kèm `@swc/helpers`, Apache-2.0) được gửi xuống trình duyệt quản trị |
| Công cụ build admin (TypeScript, sharp/libvips, caniuse-lite, PostCSS…) | Apache-2.0, LGPL-3.0-or-later (libvips), CC-BY-4.0 (caniuse-lite), MIT/ISC/BSD; chỉ dùng lúc build trong stage Node, không nằm trong image nginx |
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

## Gói Step 3 do người dùng cung cấp

`apps/practice` nhập source và tài nguyên từ `Game_Boom_Step3_Godot.zip`.
README nguồn được giữ trong `apps/practice/README.md` và bản phân phối
`licenses/STEP3_SOURCE.txt`; PNG/WAV gốc có SHA-256 trong PROVENANCE.json.
Nguồn mô tả 120 frame biến đổi từ pose gốc và 11 WAV tự tổng hợp bằng toán học,
không dùng sample/nhạc/source từ Boom Online. Đây là mô tả của nguồn cung cấp,
không phải xác minh độc lập quyền sở hữu. Không gán lại license MIT cho tài
nguyên được cung cấp; giữ nguyên lưu ý về art AI và phát hành thương mại.
Godot web export và Windows đi kèm GODOT_COPYRIGHT.txt và các notices hiện có.

## Gói UI Spec do người dùng cung cấp

Scene, script và dữ liệu demo Shop/Equipment lấy từ
`Game_Boom_UI_Spec_Godot4.zip` (Drive `1l44rdo5tILvBtT3W0qeVskXa2Miw9F-x`).
Hash ZIP và hướng dẫn art nguồn được giữ tại
`apps/practice/licenses/UI_SPEC_SOURCE.txt`, đi kèm bản Web/Windows.
Không nhập ảnh mockup phẳng hoặc asset bổ sung chưa xác minh. Giao diện tái sử dụng
PNG Step 3 hiện có và panel StyleBoxFlat; các giới hạn nguồn art Step 3 vẫn áp dụng.

## Gói giao diện Launch do người dùng cung cấp

Nền đảo nước, Píp, Nốp, logo và bọt nước trong `apps/client/art/launch` và `apps/practice/assets/ui/launch`
được cung cấp qua `BupBup_Launch_UI_Godot4.zip`. Nguồn mô tả đây là
đồ họa nguyên bản tạo riêng cho dự án, không sao chép art từ ảnh tham khảo.
Giữ nguyên tài liệu nguồn tại `apps/client/licenses/LAUNCH_ASSET_PROVENANCE.md`;
không gán lại giấy phép MIT cho các tài nguyên này.

Scene/script Launch trong `apps/practice` lấy từ cùng ZIP người dùng cung cấp,
được chỉnh để mở chế độ bot và Cửa hàng/Trang bị. Giữ nguồn tại
`apps/practice/licenses/LAUNCH_ASSET_PROVENANCE.md`.

## Gói cánh và hào quang do người dùng cung cấp

Cánh (`apps/practice/assets/cosmetics/wings`) và hào quang
(`apps/practice/assets/cosmetics/halos`) được cắt từ ảnh "Modular Wing Pack" chủ
dự án gửi ngày 2026-10-18 (`apps/practice/tools/source/modular_wing_pack.webp`),
bằng `apps/practice/tools/slice_wing_pack.gd`: chỉ đổi kênh alpha và xóa mảnh khung
bên cạnh, không vẽ thêm. Ảnh có vẻ do công cụ tạo ảnh làm cho 5 nhân vật của dự án;
nguồn gốc và quyền chưa được xác minh độc lập, không có tên/logo Boom Online.
Hash và ghi chú tại `apps/practice/licenses/WING_PACK_SOURCE.txt`; không gán lại MIT.

## Bộ sprite thú cưng do người dùng cung cấp

Skin thú cưng (`apps/practice/assets/cosmetics/pets`: thỏ, rồng, cừu, tuần lộc,
lạc đà bông, mèo, corgi, khủng long, rùa, cáo) được cắt từ 10 sprite sheet trong
`asset.7z` chủ dự án gửi ngày 2026-10-19, bằng `apps/practice/tools/slice_pet_sheets.gd`:
chỉ đổi kênh alpha, xóa đốm/mảnh khung bên cạnh và thu nhỏ, không vẽ thêm. Ảnh có vẻ
do công cụ tạo ảnh làm; nguồn gốc và quyền chưa được xác minh độc lập, không có
tên/logo Boom Online. Hash và ghi chú tại `apps/practice/licenses/PET_SHEETS_SOURCE.txt`;
không gán lại MIT.

## Bộ khối bản đồ do người dùng cung cấp

28 khối tường/thùng (`apps/practice/assets/obstacles/<tên>/00.png`, ví dụ `brick_wall`,
`round_tree`, `tnt_barrel`, `treasure_chest`) được cắt từ ảnh 28 khối chủ dự án gửi ngày
2026-10-19 (`apps/practice/tools/source/map_blocks.webp`) bằng
`apps/practice/tools/slice_map_blocks.gd`: chỉ xóa nền trắng/bóng, cắt và thu nhỏ, không vẽ
thêm. Ảnh có vẻ do công cụ tạo ảnh làm; nguồn gốc và quyền chưa được xác minh độc lập, không
có tên/logo Boom Online. Hash tại `apps/practice/licenses/MAP_BLOCKS_SOURCE.txt`; không gán
lại MIT.

## Bộ sprite nhân vật cưỡi thú do người dùng cung cấp

Hình nhân vật ngồi trên pet (`apps/practice/assets/riders/<nhân vật>/ride_*`) được cắt từ
ảnh "Rider Character Sheet" chủ dự án gửi ngày 2026-10-19
(`apps/practice/tools/source/rider_sheet.webp`) bằng `apps/practice/tools/slice_rider_sheet.gd`:
chỉ xóa nền ô màu, tách khung và thu nhỏ, không vẽ thêm. Ảnh có vẻ do công cụ tạo ảnh làm cho
5 nhân vật của dự án; nguồn gốc và quyền chưa được xác minh độc lập, không có tên/logo Boom
Online. Hash tại `apps/practice/licenses/RIDER_SHEET_SOURCE.txt`; không gán lại MIT.

## Hình Boss Vua Slime do người dùng cung cấp

Hình Boss Đại Chiến Boss (`apps/practice/assets/boss`: Vua Slime, Mini Slime Bomb, Sticky
Slime) cắt từ ảnh khung hình slime chủ dự án gửi ngày 2026-10-19
(`apps/practice/tools/source/slime_minion_frames.webp`) bằng
`apps/practice/tools/slice_slimes.gd`: chỉ tách khung và thu nhỏ, không vẽ thêm. Ảnh có vẻ do
công cụ tạo ảnh làm; nguồn gốc và quyền chưa được xác minh độc lập, không có tên/logo Boom
Online. Hash tại `apps/practice/licenses/SLIME_KING_SOURCE.txt`; không gán lại MIT.

## Hình Boss Robot Bom Dây Cót do người dùng cung cấp

Robot Bom Dây Cót (`apps/practice/assets/boss/clockwork_bot`: 4 hướng × 4 khung đi) cắt từ ảnh
`03_robot_boss_directional_original.png` trong gói `GameBoom_Robot_Boss_Event_DevPack.zip` chủ dự
án gửi ngày 2026-10-19 (giữ tại `apps/practice/tools/source/clockwork_bot_directional.webp`) bằng
`apps/practice/tools/slice_robot.gd`: chỉ tách khung, xóa đốm viền và thu nhỏ, không vẽ thêm. Gói
ghi rõ đây là concept do AI tạo; nguồn gốc và quyền chưa được xác minh độc lập, không có tên/logo
Boom Online. Hash tại `apps/practice/licenses/CLOCKWORK_BOT_SOURCE.txt`; không gán lại MIT.

## Chân dung nhân vật động do người dùng cung cấp

Chân dung động 6 khung (đứng, cười, nháy mắt) của 5 nhân vật
(`apps/practice/assets/characters/portraits/<hero>/`) cắt từ một ảnh chủ dự án gửi ngày 2026-10-21
(`apps/practice/tools/source/hero_portraits_idle.webp`) bằng `apps/practice/tools/slice_hero_portraits.gd`:
tách nền phẳng thành trong suốt, cắt và thu nhỏ, không vẽ thêm. Nguồn gốc và quyền
chưa được xác minh độc lập, không có tên/logo Boom Online. Hash tại
`apps/practice/licenses/HERO_PORTRAIT_ANIM_SOURCE.txt`; không gán lại MIT.

## Hình Boss Vua Xương Rồng và Cừu Sấm Sét do người dùng cung cấp

Hình Cừu Sấm Sét (`apps/practice/assets/boss/thunder_ram`: đi 4 hướng, đứng, hiệu ứng kỹ năng) lấy
từ ảnh nhúng trong tài liệu "Boom Boss Cừu Sấm Sét & Vua Xương Rồng" chủ dự án gửi ngày 2026-10-20
(giữ dạng WebP trong `apps/practice/tools/source`), cắt bằng `apps/practice/tools/slice_twin_bosses.gd`:
chỉ cắt khung và thu nhỏ, không vẽ thêm. Hình Vua Xương Rồng (`apps/practice/assets/boss/cactus_king`)
là bộ sprite đã chuẩn hóa của team design ("Boom_Cactus_Fixed_Pack_Godot4.zip", cùng ngày), chép
nguyên PNG và chỉ đổi tên. Tài liệu ghi đây là ảnh concept do AI tạo; nguồn gốc và quyền chưa được
xác minh độc lập, không có tên/logo Boom Online. Hash tại
`apps/practice/licenses/TWIN_BOSS_SOURCE.txt`; không gán lại MIT.

## Bộ giao diện PC "Bubble Isles" do người dùng cung cấp

Màn Tìm trận, Phòng, HUD, Kết quả, Cửa hàng và Trang bị của app PC
(`apps/practice/scripts/ui/pc`) viết lại bố cục, bảng màu và kiểu nút/panel từ
`bubble_isles_client.zip` và ảnh mockup trong Drive `1E0FY5LnrCso2Ny4MSHZOP5ElAR1wyYcl`.
Tài liệu ZIP ghi UI vẽ bằng code, thuộc dự án. Không sao chép file, avatar
chibi, tên, logo hoặc ảnh mockup; dùng lại PNG Step 3 hiện có. Hash và ghi chú
nguồn tại `apps/practice/licenses/PC_UI_KIT_SOURCE.txt`.
