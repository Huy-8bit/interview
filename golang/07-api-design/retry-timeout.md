# API retry và deadline

## Bài toán và ví dụ đầu tiên

Mobile app thấy timeout ở POST tạo đơn và tự gửi lại. Server có thể đã tạo đơn nhưng response mất. API phải định nghĩa deadline/retry từ perspective client và operation identity, thay vì coi timeout là lệnh chưa xảy ra.

## Đi từng bước qua một tình huống

Client giữ cùng idempotency key qua attempts và dùng total budget gồm backoff. Server trả status/error code cho transient overload khác validation failure. Một Retry-After có ích chỉ khi client còn budget và operation replay-safe. Không retry vô hạn để che outage.

## Hiểu cơ chế từ kết quả quan sát

Timeout nhiều lớp độc lập có thể làm tổng thời gian tăng, còn retry ở gateway/client/service cùng lúc khuếch đại attempts. Chọn retry owner và truyền deadline phù hợp qua hops. Cancellation giải phóng chờ cục bộ nhưng remote state cần query/reconciliation khi outcome chưa rõ.

## Khái niệm và mô hình làm việc

Retry tiêu thêm capacity để phục hồi transient failures; timeout là ambiguity, không chứng minh operation thất bại.

## Cơ chế và những ranh giới cần giữ

Retry replay-safe operations, exponential backoff + jitter, max attempts và total budget. Chỉ một layer sở hữu policy hoặc bounded shared retry budget.

## Áp dụng vào hệ thống thật

GET temporary 503 retry trong remaining ctx; POST mutation cần idempotency key.

## Những đường lỗi cần hiểu

Ba layers × ba attempts tạo tới 27 calls; body không replayable; retries chiếm pool.

## Lần theo bằng chứng khi có sự cố

Đo attempts/logical request, retry cause và remaining deadline trước mỗi attempt.

## Đánh đổi và giới hạn sử dụng

Không retry validation/auth hoặc permanent errors; bounded retries vẫn cần circuit/admission khi outage.

## Thực hành, debugging và kết luận

Test response bị mất sau commit, request bị hủy trước bắt đầu và failure transient rồi hồi phục. Metrics attempts và original operations riêng để thấy amplification. API docs nên nêu lúc nào được retry, dùng key gì và cách lấy trạng thái pending.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9110)
