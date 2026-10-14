# Công việc — chuyển sang website

Cập nhật 2026-10-14. Ưu tiên bản web dùng API hiện có; dừng cập nhật ứng dụng Linux.

## Đã triển khai

- [x] Thêm website `apps/web` với giao diện tiếng Việt cho desktop và điện thoại.
- [x] Trang đăng ký/đăng nhập riêng; kiểm tra form và thông báo lỗi.
- [x] Danh sách phòng chờ thật, tạo phòng mới và chọn phòng theo mã; yêu cầu đăng nhập.
- [x] Giữ API chơi khách tương thích với client cũ và smoke test.
- [x] Giữ phiên trong tab, rời/vào lại phòng, đăng xuất và xử lý phiên hết hạn.
- [x] Kết nối Colyseus thật: sảnh, sẵn sàng, trận đấu, bom, kết quả, ván tiếp theo.
- [x] Điều khiển bàn phím và cảm ứng; server giữ toàn quyền quyết định gameplay.
- [x] Thêm Nginx và service Compose web, mặc định chỉ mở trên loopback.
- [x] Thay CI đóng gói desktop bằng kiểm thử web/API/arena.
- [x] Thêm unit test, smoke qua proxy và kiểm thử Chromium desktop/mobile.
- [x] Viết hướng dẫn chạy web và chuẩn bị hostname HTTPS.

Kết quả thực thi được ghi riêng trong [VALIDATION.md](VALIDATION.md).

## Tiếp theo

- [ ] Người dùng duyệt giao diện và chơi thử giữa hai thiết bị thật.
- [ ] Chọn hostname website, cấu hình HTTPS/WebSocket sau khi được phép triển khai.
- [ ] Xác nhận GitHub Actions trên nhánh/PR sau khi push.
- [ ] Trước buổi thử đông người: thiết kế trusted proxy/rate limit và đo tải nhiều phòng.

Godot giữ nguyên trạng thái công việc có sẵn; không build gói Linux mới trong đợt này.
Các tính năng xếp hạng, lịch sử trận, khôi phục kết nối và thanh toán chưa nằm trong đợt chuyển web.
