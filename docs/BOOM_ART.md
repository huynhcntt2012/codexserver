# Bộ nhân vật và giao diện từ ZIP người dùng

Nguồn: `Game_Boom_Godot_Demo.zip`, `Game_Boom_Starter_Assets.zip` do người dùng gửi.
Dùng bản sprite sheet đã chuẩn hóa trong demo (2 cột × 10 hàng, mỗi frame 64px),
portraits và tile/effect trùng bộ Starter Assets. Không chạy hoặc nhập gameplay demo.

- Bombo, Mimi, Zin, Lala, Kai thay bốn nhân vật pastel trong toàn bộ web và PC.
- Idle, di chuyển bốn hướng và thắng dùng đúng hàng sprite sheet, 6 FPS theo metadata.
- Sân dùng ảnh cỏ, tường đá, thùng gỗ, bom nước và sáu frame splash được cung cấp.
- Form đăng nhập, sảnh, HUD, lựa chọn và kết quả dùng nền xanh đậm, viền cyan,
  nút vàng theo demo. Các nút vẫn là control thật; không dùng ảnh UI có chữ đóng sẵn.
- Chọn nhân vật vẫn là diện mạo cục bộ. Không thêm bot, tim, item hay điểm giả.
- Giữ nguyên luật server, map 15×13, protocol và bản sửa phản hồi di chuyển.

PNG được sao chép nguyên trạng, có hash ở `art/boom/PROVENANCE.json`.
Nguồn mô tả đây là art gốc tạo bằng AI, hai tư thế mỗi trạng thái, chưa phải hoạt ảnh
nhiều frame hoàn thiện. Giữ nguyên README nguồn và ghi chú trong THIRD_PARTY_NOTICES.

Verify: chọn cả năm nhân vật, đi bốn hướng, đặt bom, kết quả; kiểm tra web trên
màn hình hẹp và Windows. Không cần cài Godot khi dùng ZIP Windows đã export.
