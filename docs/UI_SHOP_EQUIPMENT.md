# Cửa hàng và Trang bị — PC / Web

Hai màn hình dùng chung source Godot trong `apps/practice`, xuất Windows và
Web tại `/practice/`. Đây là UI demo cho chế độ bot, chưa nối inventory của
bản multiplayer online.

## Chạy

Mở `apps/practice/project.godot` bằng Godot 4.4.1, nhấn F5 để vào Cửa hàng.
Thanh điều hướng mở Trang bị hoặc Vào trận. Vào trận mở menu chọn bản đồ
Step 3; nút Cửa hàng / Trang bị ở cuối menu đưa về UI.
Nhân vật đã chọn được giữ khi chuyển màn hình.

```bash
GODOT=/path/to/godot python3 scripts/build-practice.py
godot --headless --path apps/practice --script res://tests/ui.gd
```

Windows: `build/practice/suni-bot-arena-windows-x86_64.zip`.
Bản phát hành: [UI Shop/Equipment](https://github.com/huynhcntt2012/codexserver/releases/tag/ui-shop-equipment-20261015).
Web: `apps/web/public/practice/engine/`; cần build lại image web để phục vụ
bản export mới. Không tự triển khai production.

## Phạm vi

- 9 scene, 11 script UI, 18 vật phẩm, 5 nhân vật; 8 danh mục mua và 6 nhóm trang bị.
- Mua qua xác nhận; hủy không trừ tiền; từ chối thiếu tiền, vật phẩm lạ,
  cosmetic đã sở hữu và trang phục không đúng nhân vật.
- Bộ trang bị riêng cho từng nhân vật, giữ trong phiên; khởi động lại đặt lại
  tiền và inventory demo. Không thanh toán thật, không gọi API mua hàng.
- Trang bị và vật phẩm mua chưa thay đổi hình ảnh/chỉ số trong trận.
- Dùng panel Godot và PNG sẵn có; chưa tạo PNG pet/trang phục mới, 9-slice,
  animation nâng cao hoặc bố cục mobile riêng. Web dùng bàn phím máy tính.

## Sửa so với ZIP nguồn

Đổi hằng `Skin` trùng lớp engine thành `UISkin` trong 7 script. Sửa tên property
`theme_override_constants/…` trong scene để Godot áp dụng spacing/margin.
Giải phóng dialog khi hủy; tách loadout theo nhân vật; nối route quay lại UI,
đồng bộ nhân vật với menu Step 3 và hiển thị giới hạn demo.
Không ghi đè gameplay bằng phiên bản cũ trong ZIP.

Nguồn và hash: `apps/practice/licenses/UI_SPEC_SOURCE.txt`.
PNG/texture 9-slice còn thiếu theo hướng dẫn art nguồn; không cắt mockup phẳng
thành nút chứa chữ. Dùng asset nguyên bản cho bước hoàn thiện hình ảnh tiếp theo.

## Kiểm thử local

Godot 4.4.1: 21 kiểm tra UI đạt, duyệt đủ danh mục/tab/nhân vật;
127 kiểm tra gameplay đạt; smoke ba bản đồ đạt. Xuất Web và Windows thành công.
Chromium trong Docker: mở Shop/Trang bị, vào trận, điều khiển, âm thanh,
tạm dừng và chơi lại đạt. Chưa chạy executable trên máy Windows.

Ảnh: [Cửa hàng](screenshots/ui/shop.png), [Trang bị](screenshots/ui/equipment.png).
