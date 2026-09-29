# API rate limiting

## Bài toán và ví dụ đầu tiên

Một tenant gửi hàng nghìn request làm người khác timeout. Rate limit kiểm soát tốc độ nhận theo một identity và cửa sổ/policy, khác concurrency limit kiểm soát số operation đang chạy cùng lúc.

## Đi từng bước qua một tình huống

Token bucket tích token theo tốc độ và cho phép burst tới capacity. Mỗi request tiêu token; hết thì từ chối hoặc chờ theo contract. Fixed window dễ tạo burst ở ranh giới hai cửa sổ; sliding window dùng state khác để làm mượt hơn. Chọn thuật toán từ yêu cầu product và chi phí storage.

## Hiểu cơ chế từ kết quả quan sát

Trong nhiều replica, limit local nhân theo số replica nếu không có coordination. Redis atomic script hoặc cơ chế distributed phù hợp cần xử lý outage và clock assumptions. Key theo user/tenant đã xác thực tránh chỉ dựa IP khi NAT/proxy làm nhiều người dùng chung địa chỉ.

## Khái niệm và mô hình làm việc

Rate limit bound arrivals theo thời gian; concurrency limit bound in-flight work.

## Cơ chế và những ranh giới cần giữ

Token bucket cho burst capacity và refill rate; key theo authenticated tenant/route, không tin X-Forwarded-For từ nguồn tùy ý. Distributed counter cần atomic update và TTL.

## Áp dụng vào hệ thống thật

429 kèm retry guidance cho per-tenant quota; 503 cho global overload tùy contract.

## Những đường lỗi cần hiểu

Một hot tenant chiếm global bucket; retry cùng thời điểm; backend limiter unavailable có fail-open/closed trade-off.

## Lần theo bằng chứng khi có sự cố

Đo allowed/rejected theo bounded tenant tier, bucket wait và downstream saturation.

## Đánh đổi và giới hạn sử dụng

Local limiter rẻ nhưng fleet quota chỉ approximate; centralized limiter thêm dependency.

## Thực hành, debugging và kết luận

Đo allowed/rejected và latency theo nhóm hữu hạn, trả retry guidance khi thích hợp. Test burst, boundary window và Redis down. Rate limit không thay body size/concurrency bound: một request hợp lệ mỗi giây vẫn có thể rất đắt.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9110)
