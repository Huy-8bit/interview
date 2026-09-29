# Security review theo endpoint

## Bài toán và ví dụ đầu tiên

API có nhiều boundary: identity, resource ownership, input, downstream access và output. Một token hợp lệ chỉ xác định caller, không cho phép truy cập mọi order ID mà caller đưa vào.

## Đi từng bước qua một tình huống

Handler lấy identity đã kiểm chứng, query theo tenant/owner và kiểm tra policy action. Input schema/type validation chạy trước công việc đắt; body/collection size bound ngăn request tiêu memory vô hạn. Error response không cần chứa stack, SQL hay provider credential.

## Hiểu cơ chế từ kết quả quan sát

Authorization cần ở nơi có đủ thông tin resource, không chỉ gateway check token. Cache keys phải scope tenant để không trả dữ liệu chéo. TLS bảo vệ transport nhưng không thay input validation, rate limiting hay policy trong service.

## Khái niệm và mô hình làm việc

Bảo vệ identity, resource authorization, input bounds và side effects tại mọi endpoint.

## Cơ chế và những ranh giới cần giữ

Allowlist methods/content types, bounded decode, tenant-scoped queries, rate/admission limits và consistent error redaction.

## Áp dụng vào hệ thống thật

Export endpoint cần authorize dataset/tenant và signed download URL ngắn hạn.

## Những đường lỗi cần hiểu

IDOR, mass assignment, replay mutation, public pprof, unbounded decompression.

## Lần theo bằng chứng khi có sự cố

Negative tests cho cross-tenant IDs và oversized payload; review access logs bằng safe metadata.

## Đánh đổi và giới hạn sử dụng

Không coi private network là đủ authorization; service identity và user permissions khác nhau.

## Thực hành, debugging và kết luận

Test user hợp lệ truy cập resource người khác, token sai scope và oversized payload. Log security decisions với reason code hữu hạn và redaction. Chọn controls theo threat model thực của endpoint, giữ checks regression ở boundary có rủi ro.


## Đọc tiếp

- [API security theo trust boundaries](../07-api-design/api-security.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://cheatsheetseries.owasp.org/)

## Thực hành có điều kiện kiểm chứng

Dùng hai tenantsA/B và tạo resource ởA. B thử GET, PATCH, DELETE, list filter và exported download URL; tất cả access trái policy phải fail ngay cả JWT signature hợp lệ. Cache keys và query predicates đều cần tenant scope, vì DB authorization đúng nhưng cache key thiếu tenant vẫn lộ dữ liệu. Log decision reason không log token/resource contents.
