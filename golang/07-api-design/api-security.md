# API security theo trust boundaries

## Bài toán và ví dụ đầu tiên

Endpoint có auth nhưng nhận URL tùy ý để fetch thumbnail. Kẻ gọi có thể khiến server gọi một địa chỉ nội bộ mà họ không truy cập trực tiếp được. Security cần xem dữ liệu đầu vào đi tới network, query, file và quyền, không dừng ở kiểm tra token.

## Đi từng bước qua một tình huống

Validate scheme/host/address theo allowlist và policy của use case, xét redirect/DNS behavior nếu server fetch URL. Với SQL dùng parameters; với path xác định vùng được phép truy cập. Giới hạn body, số phần tử và thời gian xử lý để input hợp lệ về syntax không tiêu tài nguyên vô hạn.

## Hiểu cơ chế từ kết quả quan sát

Authentication, authorization, input validation và rate limit giải quyết các lớp khác nhau. TLS bảo vệ đường truyền không làm payload trở nên đáng tin. Tenant identity phải tới mọi query/key cache liên quan để tránh cross-tenant data exposure.

## Khái niệm và mô hình làm việc

Input từ client, proxy và downstream đều cần validation theo trust boundary.

## Cơ chế và những ranh giới cần giữ

Bound header/body/decompressed size, parameterize SQL, validate URLs/redirect destinations chống SSRF, authorize object-level, dùng TLS và credential rotation.

## Áp dụng vào hệ thống thật

Upload presign scope object/size/expiry; outbound allowlist bảo vệ metadata/private endpoints khi nhận URL.

## Những đường lỗi cần hiểu

IDOR, SSRF qua redirect/DNS rebinding, mass assignment, request smuggling ở proxy mismatch.

## Lần theo bằng chứng khi có sự cố

Security tests gồm cross-tenant IDs, oversized/recursive payloads, unexpected content type và redirect chain.

## Đánh đổi và giới hạn sử dụng

Không dùng denylist string đơn giản cho URLs; parse/resolve/connect policy phải nhất quán.

## Thực hành, debugging và kết luận

Test boundary và negative cases theo threat model endpoint. Dùng dữ liệu giả trong logs/test, kiểm tra secret redaction và error response không lộ stack/DSN. Chọn policy fail-open/fail-closed có chủ đích cho dependency bảo mật; không mặc định bỏ kiểm tra khi nó timeout.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html)

## Thực hành có điều kiện kiểm chứng

Review endpoint import-by-URL: validate scheme và destination policy trước request, kiểm lại mỗi redirect, kiểm IP resolved/connect target theo allowlist policy và deny private metadata networks khi cần. Total deadline, max response bytes và decompression bounds phải đi cùng policy. Unit URL parsing tests chưa mô phỏng DNS rebinding; integration boundary cần controlled resolver/dialer test.
