# Suni Bomb Arena — bản chơi thử Windows/Linux

Dành cho Windows 10/11 x64 hoặc Linux x86_64 có giao diện đồ họa.
Không cần cài Godot. Đây là game multiplayer: cần server do người tổ chức chạy
và ít nhất hai người chơi. Không có chế độ offline/bot trong bản này.

## Mở game

1. Giải nén toàn bộ ZIP vào một thư mục. Giữ file `.pck` cạnh ứng dụng.
2. Windows: mở `suni-bomb-arena.exe`.
   Linux: chạy `chmod +x suni-bomb-arena.x86_64`, rồi `./suni-bomb-arena.x86_64`.
3. Kết nối Internet để dùng máy chủ mặc định. Máy chủ riêng có thể dùng LAN/VPN.
4. Bản này đã điền sẵn hai địa chỉ:
   API URL: `https://api.sunifactory.com`; Arena URL: `https://arena.sunifactory.com`.
   Nếu người tổ chức đổi server, sửa hai URL trước khi Join.
   `127.0.0.1` chỉ dùng khi game và server chạy trên cùng máy.
5. Chọn **Chơi khách → Vào chơi ngay** hoặc **Đăng ký** để tạo tài khoản.
   Đăng ký cần tên 3–24 ký tự `a-z`, `0-9`, `_`, mật khẩu 10–128 ký tự và
   nhập lại mật khẩu. Tạo xong game tự đăng nhập và vào phòng.
   Lần sau chọn **Đăng nhập** bằng tài khoản đó.
6. Chờ mọi người vào cùng phòng (2–8 người), rồi tất cả bấm **Sẵn sàng**.
   Phòng đã bắt đầu sẽ không nhận thêm người; người vào sau có thể ở phòng khác.

Rời phòng giữ phiên đăng nhập khi game còn mở. Bấm **Đăng xuất** trên màn hình
vào phòng để đổi tài khoản. Đóng game hoặc hết phiên cần đăng nhập lại;
game không lưu mật khẩu/token ra đĩa. Tài khoản khách chưa thể chuyển thành tài khoản đăng ký.

## Điều khiển

- WASD hoặc phím mũi tên: di chuyển.
- Space: đặt bom; bom nổ sau 2 giây, tầm 2 ô, có kích nổ dây chuyền.
- R hoặc nút Ready: sẵn sàng ở lobby.
- Người sống cuối thắng; hết 3 phút hoặc chết đồng thời thì hòa.
- Sau kết quả 8 giây, mọi người Ready để chơi tiếp.

## Khi không kết nối được

Nếu bản cũ báo **Sign-in failed**, xóa cả Username và Password để chơi guest.
Nếu đăng nhập tài khoản đã đăng ký: username gồm 3–24 ký tự `a-z`, `0-9`, `_`;
password dài 10–128 ký tự. HTTP 422 là sai định dạng; HTTP 401 là đăng nhập bị
từ chối. HTTP 409 là tên tài khoản đã được dùng: chọn tên khác hoặc **Đăng nhập**.

Kiểm tra lại IP máy chủ, kết nối LAN/VPN và trạng thái server với người tổ chức.
Mất kết nối sẽ bị loại khỏi trận; Join lại để vào phòng mới.
Nếu bị giới hạn đăng nhập, chờ một phút rồi thử lại.
Windows build chưa ký số; xác minh nguồn gửi và checksum với người tổ chức.
Không tắt phần mềm bảo vệ để chạy file không rõ nguồn gốc.

Khi báo lỗi, gửi hệ điều hành, nội dung lỗi, bước tái hiện và file `BUILD.json`.
Không gửi mật khẩu hay token. License nằm trong thư mục `licenses` và nút
**Credits & licenses** trong game.
