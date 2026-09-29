# REST API contracts

## Bài toán và ví dụ đầu tiên

Một client cần tạo và đọc order mà không biết server dùng Go hay database nào. REST-style API tổ chức contract quanh resource, representation và HTTP semantics, giúp hai bên thay implementation độc lập trong phạm vi contract.

## Đi từng bước qua một tình huống

POST /orders tạo operation/resource theo semantics đã định; GET /orders/{id} đọc trạng thái; status và error body cho client biết accepted, not found hay conflict. Một HTTP200 chứa field error tùy ý làm monitoring và retry khó phân loại. Mutation cần operation identity khi client có thể retry sau mất response.

## Hiểu cơ chế từ kết quả quan sát

HTTP method semantics, authorization và cache behavior phải được thiết kế cùng nhau. GET không nên tạo side effect nghiệp vụ chỉ vì handler tiện dùng chung hàm. Response schema cần phân biệt missing/null/empty và versioning tương thích; pagination đặt bound để một call không trả toàn bộ dữ liệu.

## Khái niệm và mô hình làm việc

HTTP API contract gồm resource, method semantics, representation và errors; JSON endpoint chưa đủ để nói thiết kế tốt.

## Cơ chế và những ranh giới cần giữ

GET an toàn đọc; PUT biểu diễn replace theo contract; PATCH cập nhật phần; POST thường tạo action/resource. Status phải phân biệt validation, auth, conflict và overload.

## Áp dụng vào hệ thống thật

POST /orders trả ID và trạng thái; async processing trả 202 với status URL khi work đã durable.

## Những đường lỗi cần hiểu

GET có side effect bị proxy retry; trả 200 cho mọi lỗi làm monitoring/client retry sai.

## Lần theo bằng chứng khi có sự cố

Contract tests cho methods/status, idempotency và field compatibility; trace route templates.

## Đánh đổi và giới hạn sử dụng

Không ép workflow phức tạp thành CRUD giả; action endpoint rõ có thể tốt hơn.

## Thực hành, debugging và kết luận

Test contract trên success và lỗi, gồm malformed JSON, unsupported method, oversized body và unauthorized resource. Trace theo route template thay vì URL chứa ID để metrics không nổ cardinality. Một API dễ dùng giúp client xử lý failure đúng, không chỉ có path đặt tên đẹp.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9110)
