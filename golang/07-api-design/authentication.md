# Authentication và authorization

## Bài toán và ví dụ đầu tiên

Một request gửi user_id trong body không chứng minh người gửi là user đó. Authentication xác định danh tính từ credential được kiểm chứng; authorization sau đó quyết định danh tính ấy được làm gì với resource cụ thể.

## Đi từng bước qua một tình huống

Middleware kiểm tra session/token theo cơ chế hệ thống, tạo identity đã xác thực rồi handler dùng identity để scope query. Endpoint /orders/{id} vẫn phải kiểm tra order thuộc tenant/người có quyền, không chỉ token hợp lệ. Trả lỗi theo policy mà không lộ thêm thông tin resource nhạy cảm.

## Hiểu cơ chế từ kết quả quan sát

Token expiry, revocation, key rotation và clock policy là phần lifecycle. Đặt identity vào context values tiện cho request nhưng không biến dữ liệu client tự khai thành trusted. Secret/token phải được che khỏi log, trace attributes và error messages.

## Khái niệm và mô hình làm việc

Authentication xác định actor; authorization kiểm tra actor được làm gì với resource cụ thể.

## Cơ chế và những ranh giới cần giữ

Validate credentials ở boundary, tạo principal đã xác thực; service kiểm tra tenant/resource/action. Không chỉ dựa user ID từ request body.

## Áp dụng vào hệ thống thật

Order lookup dùng tenant predicate và policy; service-to-service identity không mặc nhiên bypass user permission.

## Những đường lỗi cần hiểu

JWT hợp lệ nhưng đọc order tenant khác; spoof forwarded identity headers.

## Lần theo bằng chứng khi có sự cố

Negative tests cross-tenant, expired credentials, missing scopes; log decision metadata không token.

## Đánh đổi và giới hạn sử dụng

Gateway auth giảm lặp nhưng domain authorization vẫn ở service; cache policy cần invalidation.

## Thực hành, debugging và kết luận

Test không credential, credential hết hạn, issuer/audience sai và user hợp lệ truy cập resource người khác. Phân biệt tỷ lệ auth failure với dependency auth service down. Đừng cache permission lâu mà không có freshness policy cho quyền bị thu hồi.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)
