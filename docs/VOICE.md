# Chat trong trận và voice đội (app PC)

Chỉ có trên app PC (`apps/practice`); web `/demo` dùng cùng build nhưng không bật thêm gì
cho voice. Code: [voice_chat.gd](../apps/practice/scripts/voice_chat.gd) (micro, mã hóa,
phát), [match_chat.gd](../apps/practice/scripts/ui/pc/match_chat.gd),
[voice_panel.gd](../apps/practice/scripts/ui/pc/voice_panel.gd),
[voice.ts](../apps/arena/src/voice.ts) (chuyển tiếp trên arena).

## Chat trong trận

- Nút **Trò chuyện** góc dưới trái sân, có số tin chưa đọc. **Enter** mở và gõ, **Enter**
  gửi, **Esc** thoát ô nhập (phím lại điều khiển nhân vật; khi đang gõ không đi, không
  đặt bom).
- Tab **Tất cả**, **Đội** (Đại Chiến Boss: cả đội; đấu tự do không chia đội), **Hệ thống**
  (bắt đầu/kết thúc trận, người bị loại).
- Online: dùng chat phòng có sẵn (`POST/GET /v1/chat`, kênh `room`, lọc từ và giới hạn
  tốc độ của API). Luyện tập offline: tin chỉ trên máy, bot thỉnh thoảng nói.

## Voice

- Micro 16 kHz mono, G.711 mu-law, khung 60 ms (960 byte), gửi qua WebSocket arena
  (`ROOM_DATA_BYTES` kiểu 2, xem [ARENA.md](ARENA.md)). Arena chỉ chuyển tiếp: không giải
  mã, không lưu; tự gắn id người nói (session), bỏ khung sai định dạng/quá dài, tối đa
  24 khung/giây/người; người chưa vào ghế không gửi được.
- Kênh **toàn bộ**: mọi người trong phòng. Kênh **đội**: đồng đội; trong Đại Chiến Boss là
  cả đội, đấu tự do không ai nhận.
- **Nhấn để nói** (mặc định, phím `V`): micro chỉ mở khi giữ phím. **Mic mở**: micro chạy
  suốt trận, chỉ gửi khi giọng vượt độ nhạy. Lọc tiếng ồn bỏ âm thanh nhỏ.
- Bảng **Voice**: người trong kênh (đang nói / đang nghe), **Tắt voice** từng người (chỉ
  trong trận), tắt mic, tắt loa, thanh mức micro. Offline chỉ báo voice dùng khi online.
- Cài đặt › Âm thanh › **Cài đặt giọng nói**: bật/tắt, kênh, chế độ, phím nói (không trùng
  phím chơi), âm lượng micro / người khác, độ nhạy, lọc ồn, kiểm tra micro, danh sách chặn.
  Lưu trong `user://settings.cfg` mục `voice`.
- Chưa có: khử vọng (echo), đo ping, codec nén hơn mu-law (khoảng 16 KB/s mỗi người nói).

## Kiểm thử

```bash
npm test                                   # arena: tests/voice.test.ts (wire thật)
godot --path apps/practice --script res://tests/voice.gd
```
