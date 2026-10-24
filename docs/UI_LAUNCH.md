# Màn hình đăng nhập Godot

`apps/client/scripts/launch_view.gd` dựng Control native theo UI Spec Launch
1280×720, scale đồng nhất và căn giữa trong viewport hiện có. Nền phủ cửa sổ.
Dùng bộ art Launch được cung cấp, giữ nguồn tại `apps/client/licenses`.

- Đăng nhập/đăng ký dùng adapter hiện có; chỉ mở chọn phòng sau xác thực.
- Chơi thử dùng tài khoản khách online, vẫn cần API/arena.
- Nhớ tên chỉ lưu username; không lưu mật khẩu/token.
- Cài đặt chứa âm lượng, toàn màn hình và URL server hiện có.
- 1P/2P giải thích cách chơi; chưa có chế độ hai người cùng bàn phím.
- Quên mật khẩu và sự kiện thông báo trạng thái chưa hỗ trợ/chưa có nội dung.
- Nhấp thông báo dưới form để đọc đầy đủ lỗi.

Kiểm tra: Godot 4.4.1 parse/runtime bằng `scripts/check-godot.py`;
kiểm thử tài khoản qua `apps/client/tests/accounts.gd` với server local.
