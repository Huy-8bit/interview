# Secrets: distribution, storage và rotation

## Bài toán và ví dụ đầu tiên

Credential bị lộ qua error log có thể gây hại dù repository không commit secret. Secret management bao phủ source, build, runtime, telemetry, rotation và thu hồi, không chỉ chọn một nơi lưu password.

## Đi từng bước qua một tình huống

Main nhận credential qua kênh môi trường quản lý, xây client và chỉ log phần config không nhạy cảm. Pool connections có thể tiếp tục dùng credential cũ sau rotation; cần policy tạo mới/drain phù hợp DB/provider. Permissions của identity nên đủ cho workload, không dùng quyền admin tiện lợi.

## Hiểu cơ chế từ kết quả quan sát

Secret trong env/file có thể bị đọc qua quyền process/filesystem tương ứng. Secret manager giảm một số rủi ro phân phối nhưng thêm dependency và refresh policy. Context values, traces và panic dumps cũng có thể giữ hoặc lộ dữ liệu nếu truyền secret quá rộng.

## Khái niệm và mô hình làm việc

Secret exposure có thể qua code, image layer, logs, crash dumps và telemetry.

## Cơ chế và những ranh giới cần giữ

Prefer workload identity/secret manager, least privilege, encryption at rest và access audit; rotation với overlap/reload và rollback policy.

## Áp dụng vào hệ thống thật

Separate credentials per environment/service; migration role khác application DML role.

## Những đường lỗi cần hiểu

Commit secret vào git, dump env, share admin DB role, expired credential reconnect storm.

## Lần theo bằng chứng khi có sự cố

Audit access/version/key IDs, repo secret scanning và rotation drills; redact content.

## Đánh đổi và giới hạn sử dụng

Environment variables dễ dùng nhưng dễ lọt qua diagnostics; chọn cơ chế theo runtime/threat model.

## Thực hành, debugging và kết luận

Test rotation/revocation với credential thử và confirm không xuất hiện trong artifacts/logs. Khi lộ, quy trình cần thu hồi/đổi và đánh giá access theo owner hệ thống. Code examples dùng placeholders có nghĩa, không hardcode credential thật.


## Đọc tiếp

- [API security theo trust boundaries](../07-api-design/api-security.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://cheatsheetseries.owasp.org/)
