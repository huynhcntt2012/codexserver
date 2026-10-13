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
