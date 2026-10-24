# EXP sau trận và cấp nhân vật

Theo đặc tả "Match EXP v1.1". Người chơi nhận EXP sau mỗi trận PvP online hoặc Đại Chiến Boss hợp
lệ; EXP tăng cấp hiển thị ở sảnh và thanh trên (`Lv.12`, thanh tiến độ). EXP tách khỏi vàng, kim
cương, Huy Hiệu Boss, điểm xếp hạng và nhiệm vụ.

Code: [progression.py](../apps/api/app/progression.py) (API), [game.ts](../apps/arena/src/game.ts)
và [boss.ts](../apps/arena/src/boss.ts) (đếm số liệu), `pc_online.gd` (bảng EXP cuối trận),
`/admin/exp/` (Rule Editor). Bảng: [016_progression.sql](../infra/postgres/016_progression.sql).

## Ai tính, khi nào

- Arena đếm số liệu trong mô phỏng và gửi kèm sự kiện `match` / `boss_raid` (token dịch vụ). Client
  chỉ gửi lệnh chơi, không bao giờ gửi EXP.
- API chốt EXP trong cùng transaction lưu trận: mỗi `(match_id, người chơi)` đúng một award
  (`UNIQUE`), mỗi nguồn một dòng ledger. Gửi lại sự kiện 10 lần vẫn một award.
- Award lưu rule id/version, hệ số sự kiện, hệ số ngày, breakdown và số liệu. Đổi rule sau đó không
  tính lại trận cũ.
- Người không đủ điều kiện có award 0 EXP kèm `reason` và mã hỗ trợ (8 ký tự đầu id award).

## Số liệu arena gửi

PvP (`results[]`): `kills` (KO: người bị loại khỏi ván, không tính tự hạ), `assists` (người khác
killer có hit vào nạn nhân trong 10 giây trước khi bị loại, 1 lần/nạn nhân), `hits` (bom của mình
trúng đối thủ, 1 lần cho mỗi cặp bom × nạn nhân, kể cả khi khiên/thú cưỡi đỡ), `active_ms` (mỗi
hành động cộng tối đa 5 giây kể từ hành động trước), `groups` (số nhóm hành vi: đi qua 3 ô khác
nhau, bom phá thùng/trúng người, hit, dùng vật phẩm). Chế độ hiện tại không có cứu đồng đội hay mục
tiêu bản đồ nên `rescues`/`objectives` luôn 0.

Boss (`raiders[]`): ngoài `damage` (chỉ HP thật bị trừ, không overkill), `support`, `actions`,
`active_ms` có thêm `rescues` (phá bong bóng cứu đồng đội), `phases` (số phase Boss mà người chơi có
hành động hoặc gây sát thương); `team_size` là số người lúc bắt đầu. Chưa có cơ chế ngắt chiêu, quái
triệu hồi hạ được hay mục tiêu phụ: các dòng này luôn 0.

## Công thức (rule mặc định v0)

| PvP                                | EXP                          | Tối đa            |
| ---------------------------------- | ---------------------------- | ----------------- |
| Hoàn thành / Thắng / Hòa / Thua    | 50 / 100 / 50 / 25           | 1 lần             |
| KO / hỗ trợ / hit / cứu / mục tiêu | 40 / 20 / 8 / 15 / 10        | 5 / 5 / 5 / 3 / 5 |
| Trần trận                          | Thắng 450, hòa 300, thua 250 |                   |

Không có người thắng: ai còn trụ tới cuối là hòa, người bị loại trước là thua.

| Boss                                           | EXP                                                | Tối đa            |
| ---------------------------------------------- | -------------------------------------------------- | ----------------- |
| Hoàn thành / Thắng / Thua hoặc hết giờ         | 50 / 150 / 25                                      | 1 lần             |
| Sát thương                                     | `round_half_up(120 × min(1, damage / hp_max × n))` | 120               |
| Ngắt chiêu / cứu / quái / phase / mục tiêu phụ | 15 / 20 / 10 / 10 / 15                             | 3 / 3 / 4 / 3 / 3 |
| Trần trận                                      | Thắng 500, thua/hết giờ 180                        |                   |

Thứ tự: điều kiện → cộng dòng → `min(raw, trần)` → × hệ số sự kiện (lúc trận bắt đầu, 1 / 1,25 /
1,5 / 2, không cộng dồn) → × hệ số ngày (Boss: lượt hợp lệ 1–5 ×1, 6–10 ×0,5, từ 11 ×0,25, theo ngày
Asia/Ho_Chi_Minh lúc chốt) → làm tròn half-up.

## Điều kiện nhận EXP

- PvP: phòng luyện tập có bot luôn 0 (`PRACTICE`). Cần ≥ 2 nhóm hành vi (`AFK`) và
  `active_ms ≥ min(30 giây, ceil(0,4 × thời lượng))`, hoặc bị loại sớm sau ≥ 10 giây hoạt động
  (`NOT_ACTIVE`).
- Boss: `ABORT` = 0; phòng riêng 0 trừ khi rule bật `reward_private`; có mặt, số hành động
  (chống AFK) và đóng góp (≥ 1% HP hoặc ≥ 3 hỗ trợ) lấy theo điều kiện của sự kiện Boss, áp dụng cho
  mọi kết quả.

## Cấp

`required_xp(L) = 100 + 40(L−1) + 10(L−1)²` (curve v1, cố định trong code): Lv.1 100, Lv.2 150,
Lv.5 420, Lv.12 1750. Lưu `level`, `xp_in_level`, `total_xp`; một trận đủ lên nhiều cấp thì trừ lần
lượt từng ngưỡng. Cấp tối đa 100: chạm trần chỉ tăng `total_xp`. Đổi curve khi đã có người chơi thật
cần migration riêng.

## API

Người chơi: `GET /v1/progression/me`, `GET /v1/progression/me/matches` (20 trận gần nhất),
`GET /v1/matches/{match_id}/exp` (404 tới khi trận được chốt; client thử lại vài lần). `match_id`
PvP là `<process>.<room>.<round>` (snapshot `matchId`), Boss là `raid.matchId`.

Admin (`/admin/v1`): `GET /exp/rules` (rule đang áp dụng, các phiên bản, mặc định, xem trước, level
curve), `POST /exp/rules/preview`, `POST /exp/rules` và `PUT|DELETE /exp/rules/{id}` (nháp, quyền
`liveops`), `POST /exp/rules/{id}/publish` (owner; áp dụng cho trận bắt đầu sau lúc phát hành),
`GET /exp/stats?days=7`, `GET /exp/players/{id}`, `POST /exp/players/{id}/adjust` (owner,
`MANUAL_ADJUSTMENT` có lý do và `request_id`, chỉ cộng). Mọi thay đổi ghi audit `exp.*`.
Trang Người chơi: dòng "Cấp độ" ở tab Thông tin và tab "Cấp độ" (Lv, EXP cấp hiện tại, tổng EXP,
30 trận gần nhất có EXP) đọc từ `GET /exp/players/{id}`.

Level bắt đầu từ Lv.1, 0 EXP khi áp dụng hệ thống này: hồ sơ demo của client (khách) cũng về Lv.1
thay cho Lv.12 cũ; trước đó server không lưu level nên không có dữ liệu cũ cần chuyển.

Trên database đang chạy, áp migration một lần:

```bash
docker compose exec -T postgres psql -U suni -d suni < infra/postgres/016_progression.sql
```

## Chưa làm

- Bảng xếp hạng "Kinh nghiệm" vẫn tính theo trọng số riêng ([LEADERBOARD.md](LEADERBOARD.md)),
  chưa đọc `total_xp`.
- Không có endpoint settle nội bộ riêng (`/internal/matches/{id}/settle-exp`): EXP chốt ngay khi
  ingest lưu trận. Chưa có hàng đợi/outbox cho phần thưởng khác.
- Báo cáo bất thường mới có top EXP trong ngày và thống kê lý do; chưa phát hiện cặp tài khoản đánh
  nhau lặp lại.
