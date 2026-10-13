# Suni Bomb Arena — bản chơi thử LAN/VPN

Dành cho Windows 10/11 x64 hoặc Linux x86_64 có giao diện đồ họa.
Không cần cài Godot. Đây là game multiplayer: cần server do người tổ chức chạy
và ít nhất hai người chơi. Không có chế độ offline/bot trong bản này.

## Mở game

1. Giải nén toàn bộ ZIP vào một thư mục. Giữ file `.pck` cạnh ứng dụng.
2. Windows: mở `suni-bomb-arena.exe`.
   Linux: chạy `chmod +x suni-bomb-arena.x86_64`, rồi `./suni-bomb-arena.x86_64`.
3. Kết nối cùng mạng LAN hoặc VPN với máy chủ.
4. Nhập hai URL do người tổ chức cung cấp. Ví dụ nếu IP máy chủ là `192.168.1.50`:
   API URL: `http://192.168.1.50:8000`; Arena URL: `http://192.168.1.50:2567`.
   `127.0.0.1` chỉ dùng khi game và server chạy trên cùng máy.
5. Để username/password trống rồi bấm **Join arena** để chơi bằng tài khoản khách.
6. Chờ mọi người vào cùng phòng (2–8 người), rồi tất cả bấm **Ready**.
   Phòng đã bắt đầu sẽ không nhận thêm người; người vào sau có thể ở phòng khác.

## Điều khiển

- WASD hoặc phím mũi tên: di chuyển.
- Space: đặt bom; bom nổ sau 2 giây, tầm 2 ô, có kích nổ dây chuyền.
- R hoặc nút Ready: sẵn sàng ở lobby.
- Người sống cuối thắng; hết 3 phút hoặc chết đồng thời thì hòa.
- Sau kết quả 8 giây, mọi người Ready để chơi tiếp.

## Khi không kết nối được

Kiểm tra lại IP máy chủ, kết nối LAN/VPN và trạng thái server với người tổ chức.
Mất kết nối sẽ bị loại khỏi trận; Join lại để vào phòng mới.
Nếu bị giới hạn đăng nhập, chờ một phút rồi thử lại.
Windows build chưa ký số; xác minh nguồn gửi và checksum với người tổ chức.
Không tắt phần mềm bảo vệ để chạy file không rõ nguồn gốc.

Khi báo lỗi, gửi hệ điều hành, nội dung lỗi, bước tái hiện và file `BUILD.json`.
Không gửi mật khẩu hay token. License nằm trong thư mục `licenses` và nút
**Credits & licenses** trong game.
