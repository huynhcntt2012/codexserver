# GAME BOOM — STEP 3: 3 bản đồ / Animation / Âm thanh / AI né bom

**Game prototype 2D Godot 4, chơi offline 1 người + 3 bot trên Windows/Linux/macOS.** Bản này **tiếp nối bộ Step 2**, giữ năm nhân vật và cơ chế gameplay nhưng nâng cấp 3 bản đồ chọn được từ menu, âm thanh gốc và AI né nổ. **Không dùng sprite/source/musical sample thuộc Boom Online**.

## Chạy project

1. Giải nén ZIP, giữ nguyên các thư mục.
2. Tải **Godot Engine 4.x** từ https://godotengine.org/download/ (khuyên dùng 4.3 trở lên, bản standard).
3. Godot → **Import** → chọn `project.godot` → **Import & Edit**.
4. Đợi Godot import các ảnh/audio → nhấn **F5** để chạy.
5. Chọn một trong **5 nhân vật** và **3 bản đồ**, bấm **BẮT ĐẦU CHƠI**.

| Phím | Chức năng |
|---|---|
| WASD / phím mũi tên | Di chuyển 4 hướng |
| Space | Đặt bom, ngòi ~2.4 giây |
| R | Chơi lại bản đồ đang chọn |
| Esc | Tạm dừng/tiếp tục |
| M | Bật/tắt toàn bộ nhạc & hiệu ứng |

Bạn có 3 tim; mỗi bot có 1 tim. Trong 180 giây, phá vật cản, nhặt 3 loại item (thêm bom, tầm nổ, giày tăng tốc) và loại 3 bot. Bom nổ theo hình chữ thập; tường chắn nổ, thùng chặn nổ rồi bị phá, bom khác gây dây chuyền.

## Những thay đổi trong Step 3

### 1. 3 bản đồ JSON (thay vì map ngẫu nhiên duy nhất)

- **Công Viên Kẹo (`park.json`):** Cỏ xanh, thùng gỗ, 13 khối phá được, bot di chuyển chậm nhất.
- **Lâu Đài Băng (`frost.json`):** Nền tuyết, tường đặc biệt, thùng kim loại, 21 khối phá được, bot nhanh hơn.
- **Đảo Nắng Vàng (`coast.json`):** Cát vàng, thùng tròn, 28 khối phá được, bot phản ứng nhanh nhất.

Các layout 15×11 viết ở `levels/*.json`, dùng **`.` = ô trống**, **`#` = tường không phá**, **`C` = thùng phá được**. Kích thước ô **64×64 px**. Vị trí xuất phát: (1,1), (13,1), (13,9), (1,9). Mỗi spawn có vùng đi đủ rộng để né bom — được kiểm tra tự động bằng BFS trong Python.

Muốn tạo bản đồ mới, sao chép một JSON, sửa các trường `id/name/theme/crate/wall/bomb/fx/bot_step/bot_bomb/layout`, cập nhật `LEVEL_FILES` và danh sách lựa chọn trên menu trong `scripts/game.gd`.

### 2. Animation 5 nhân vật

- Mỗi nhân vật có **4 hướng di chuyển × 6 frame**, tổng **120 PNG RGBA 64×64** mới ở `assets/animations/`.
- Các frame mới được tạo bằng biến đổi hình học nhẹ từ hai pose gốc (nâng/hạ thân, nén/giãn), **không phải 120 minh họa vẽ mới từ đầu**.
- Giữ các action cũ: `idle`, `place_bomb`, `throw_item`, `hit`, `win`, `lose` (2 frame từ Step 2).
- `scripts/hero_sprite.gd` nạp frame, chạy hoạt ảnh di chuyển ở 12 fps, nhún nhẹ; nhân vật di chuyển theo ô với tween Ease-Out.

Lưu ý: trước khi phát hành thương mại, nên chỉnh tay consistency/bàn chân/bóng và thêm frame vẽ độc lập nếu cần chất lượng production.

### 3. Âm thanh gốc

`assets/audio/` có **11 tệp WAV**, tạo bằng synth toán học/Python, không tải/sao chép bất kỳ track nào: `ui_select`, `round_start`, `footstep`, `place_bomb`, `bomb_tick`, `explosion`, `collect`, `hit`, `victory`, `defeat`, `music_loop`.

Audio player được pool thành 10 kênh SFX + 1 kênh nhạc nền. Bấm `M` để tắt/bật. Tất cả âm thanh 16-bit mono, 22.05 kHz. Nhạc nền dài 8s, tự phát lại khi kết thúc.

### 4. AI mới

- Bot không đi ngẫu nhiên toàn phần như Step 2.
- Dự đoán các ô nằm trong vùng nổ của những quả bom đang đếm ngược.
- Khi gặp nguy hiểm, dùng **BFS** tìm đường tới ô an toàn, tránh thùng/tường/bom/nhân vật khác.
- Trước khi đặt bom, bot tìm thử một lối rút trong tối đa 4 ô (không tự ý đặt nếu không tìm thấy lối thoát).
- Khi tương đối an toàn, bot tìm ô có ích để nhặt item, phá thùng, áp sát đối thủ; độ nhanh & nhịp đặt bom được cấu hình theo map.

Đây là **AI heuristic cho bản demo**, chưa phải AI chiến thuật tối ưu: không giải quyết mọi tình huống nhiều bom liên hoàn, cũng chưa dự đoán thay đổi bản đồ nhiều bước.

## Kiểm tra

Đã chạy thành công kiểm tra **tĩnh** bằng Python ở `tools/verify_step3.py`: 3 JSON, lối thoát spawn, texture đủ bộ, 120 sprite RGBA, 11 WAV hợp lệ, đường dẫn source. **Chưa được kiểm thử runtime trong Godot ở môi trường tạo gói này** do không có executable Godot và không tải được từ Internet.

Trên máy đã có Godot, chạy smoke test tích hợp:

```bash
godot --headless --path /duong/dan/Game_Boom_Step3_Godot --script res://tests/headless_smoke.gd
```

Hoặc vào thư mục project rồi chạy:

```bash
godot --headless --path . --script res://tests/headless_smoke.gd
```

Test Godot thử load scene, tạo lần lượt 3 map, kiểm tra fighter/bom/hiệu ứng. Nếu báo parser/runtime, gửi log `--headless` để sửa theo đúng engine version. *Godot binary trên một số máy tên `godot4`.*

### File và thư mục quan trọng

```text
Game_Boom_Step3_Godot/
├── project.godot
├── scenes/main.tscn
├── scripts/
│   ├── game.gd                 # gameplay, menu, 3 bản đồ, BFS, SFX
│   └── hero_sprite.gd          # 6-frame directional animation
├── levels/
│   ├── park.json
│   ├── frost.json
│   └── coast.json
├── assets/
│   ├── animations/             # 120 frame mới
│   ├── level_previews/         # ảnh thu nhỏ 3 bản đồ
│   ├── audio/                  # 11 WAV tự tạo
│   └── ...                     # assets Step 2: sprites, tiles, items, FX
├── tests/headless_smoke.gd
├── tools/verify_step3.py
├── CODEX_TASK.md
└── README.md
```

## Về bản quyền

Bộ này dùng sprite game được tạo ở các bước trước và hiệu ứng synth mới. Làm game thể loại đặt bom theo ô không đồng nghĩa sao chép nhân vật, tên, logo, giao diện, âm thanh hoặc bản đồ từ Boom Online. Nếu có ý định kinh doanh thương mại, hãy tiếp tục rà soát asset AI và tính độc đáo của phong cách, kiểm thử trên engine thật, rồi mới public.

## Giai đoạn 4 được đề xuất

Tách `game.gd` thành các hệ thống độc lập, thêm chế độ LAN 2–4 người (state sync), quản lý phòng, server authoritative chạy Ubuntu Docker, dùng Godot client. **Bước 3 hiện tại offline**, chưa có backend hoặc tính năng online.
