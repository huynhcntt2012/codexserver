# Bản sửa phản hồi di chuyển

## Thay đổi

- Server giữ tối đa một hướng di chuyển tới khi hết cooldown 150 ms, thay vì
  bỏ lệnh đến sớm. Hướng mới ghi đè hướng cũ; bom vẫn ưu tiên. Không tăng tốc game.
- Web gửi ngay lần nhấn đầu, lặp sau mỗi 150 ms tính từ lần gửi thực tế.
  Dùng nhịp vẽ của màn hình thay giới hạn 30 FPS và làm mượt chuyển ô.
- PC gửi ngay khi đổi hướng và ưu tiên hướng vừa nhấn, lặp mỗi 150 ms.
- Hai client nhích hình ảnh tối đa ¼ ô trong lúc chờ server, chỉ nếu ô kế tiếp
  không có vật cản trong snapshot hiện tại. Không thay vị trí/va chạm thật.
  Nếu chưa được xác nhận sau 250 ms, hình ảnh trở về vị trí thật; không tiếp tục
  dự đoán nhiều ô khi mạng gián đoạn. Chết, đổi ván hoặc rời phòng xóa trạng thái.
- Vì lệnh được giữ để xử lý đúng một lần, một lần nhấn ngắn đến trong cooldown
  có thể hoàn tất bước sau khi đã nhả phím; không tự di chuyển thêm nhiều bước.

## Giới hạn

Đây là phản hồi hình ảnh có giới hạn, chưa phải dự đoán toàn bộ vị trí với số thứ tự
input và server reconciliation. Không loại bỏ ping Internet. Bom, damage, thắng thua
và vị trí thật vẫn chờ server. Wire protocol không đổi; client cũ vẫn kết nối được.

## Verify

So sánh nhấn nhanh, giữ phím, đổi hướng, đi cạnh tường/thùng/bom và thả phím.
Dùng hai client để kiểm tra va chạm và kết quả. Khi mạng chậm, phản hồi ban đầu có
thể xuất hiện trước bước thật nhưng không được vượt sang ô khác khi chưa xác nhận.

Kiểm thử: buffer đến sớm/ghi đè/không tăng tốc/xóa sau ván; hiệu ứng cục bộ bị chặn
bởi tường, bom, người chơi; timeout khi thiếu snapshot; Godot headless và trận thật.
