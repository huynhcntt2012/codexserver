# Bụp Bụp — bản giao diện để verify

Web và Godot Windows dùng bảng màu pastel, nút bo tròn, bốn nhân vật SVG,
ô cỏ, tường đá, thùng gỗ và bóng nước theo tám ảnh tham chiếu do người dùng cung cấp.
Giữ bản đồ 15×13 và gameplay server hiện có; không đổi protocol.

## Phạm vi

- Trang vào chơi/đăng nhập, danh sách phòng web, phòng chờ, trận đấu, kết quả.
- Màn chọn Bông, Mây, Lá, Nắng: diện mạo cục bộ, không lưu sau khi đóng app,
  không đồng bộ sang người chơi khác. Các nhân vật có cùng sức mạnh.
- Kết quả lấy từ server; tự trở về phòng chờ để sẵn sàng ván tiếp theo.
- Chưa có xếp hạng, shop, xu/EXP, quà đăng nhập, danh sách bạn bè, đội 2v2 hoặc
  vật phẩm tăng sức mạnh. Không hiển thị giá trị giả từ bản thiết kế.
- Windows giữ luồng vào phòng tự động; web có danh sách chọn/tạo phòng.

## Verify Windows

Giải nén toàn bộ ZIP rồi chạy `suni-bomb-arena.exe` bên cạnh file `.pck`.
Mặc định kết nối `https://api.sunifactory.com` và `https://arena.sunifactory.com`;
có thể đổi địa chỉ ngay trong form. Cần hai người chơi cùng sẵn sàng.
WASD/mũi tên để di chuyển, Space đặt bóng, R sẵn sàng.
Nhấn **Nhân vật** để đổi diện mạo trên máy mình.

Bản Windows được export bằng Godot 4.4.1. Máy build là Linux nên chưa chạy
file `.exe` trực tiếp trên Windows; cần người dùng verify bước này.

## Kiểm tra thực hiện

- Node 22: 5 web adapter tests, 13 arena tests (gồm WebSocket thật), lint, build.
- Playwright: luồng auth và trận đấu desktop/mobile, 3 tests đạt (bao gồm chọn nhân vật và tải SVG).
- Godot 4.4.1: kiểm tra editor/runtime, lobby hai client thật, countdown,
  kết quả, ván tiếp theo và rejoin.
- Ảnh review: `docs/screenshots/bup-web` và `docs/screenshots/bup-pc`.
- Không deploy production; web preview local ở cổng 18082.
