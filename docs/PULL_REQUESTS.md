# Chia thay đổi thành PR nhỏ

Repository khởi đầu chưa có commit/nhánh remote, cần commit nền trước khi tạo PR.
Các nhóm review theo thứ tự:

1. **Add monorepo conventions**: hướng dẫn, ignore, format và copyright.
2. **Add authoritative arena**: npm workspace, mô phỏng, room/JWT, unit và network tests.
   Kiểm tra `npm run lint`, `npm test`, `npm run build` trên Node 22.
3. **Add account API**: FastAPI, SQL schema, Redis limiter, uv lock và API tests.
   Kiểm tra Ruff, pytest.
4. **Add Godot multiplayer client**: pixel placeholders, UI, adapter, smoke test.
   Kiểm tra Godot parse/runtime và kết nối thật; kèm ảnh UI.
5. **Add deployment and CI**: Dockerfiles, Compose, CI/CD, scripts và runbook.
   Build images, healthchecks, smoke và export PCK.

PR phụ thuộc dùng base nhánh trước; sau merge đổi base về nhánh mặc định.
Không tự merge. Không commit `.env`, database, dependencies hoặc artifacts.
Ghi rõ test local và trạng thái GitHub Actions thực tế, không đánh đồng hai loại.

## Xuất bản các nhánh đã chuẩn bị

Bốn nhánh `suni/01-arena` đến `suni/04-delivery` được xếp chồng trên commit nền
`main`. Nội dung PR nằm trong `docs/prs/`. Từ workspace có các nhánh này, đăng
nhập GitHub bằng chính user đang chạy Git rồi thực hiện:

```bash
gh auth login --hostname github.com --git-protocol https --web --scopes workflow
gh auth setup-git
bash scripts/open-prs.sh
```

Script kiểm tra remote, trạng thái sạch và đăng nhập trước khi push các nhánh
bằng một thao tác atomic, không force. Sau đó tạo bốn draft PR; nếu đã có PR mở
cho nhánh tương ứng thì in lại URL. Script không merge hoặc deploy.
