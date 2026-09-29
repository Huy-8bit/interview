# Timeout và failure detection

## Bài toán và ví dụ đầu tiên

Một service không trả lời trong 500 ms. Caller cần giới hạn chờ để giải phóng tài nguyên, nhưng chưa biết service chết, mạng chậm hay operation vừa commit. Timeout là tín hiệu thiếu tiến triển theo budget của caller, không là kết luận chắc chắn về remote state.

## Đi từng bước qua một tình huống

Trên timeline send→commit→response, response có thể bị mất sau commit. Caller chuyển operation sang unknown/pending rồi query status hoặc retry cùng identity. Nếu là read không side effect, retry thường đơn giản hơn nhưng vẫn dùng budget còn lại và làm tăng tải.

## Hiểu cơ chế từ kết quả quan sát

Deadline nên đi qua chuỗi calls để tầng dưới không làm việc lâu hơn nhu cầu phía trên. Timeout mỗi hop độc lập có thể cộng thành tổng rất dài. Server-side timeout bổ sung bảo vệ khi cancellation không tới được server, nhưng không thay protocol xử lý kết quả chưa rõ.

## Khái niệm và mô hình làm việc

Timeout là suspicion về progress, không chứng minh remote process chết hoặc operation chưa commit.

## Cơ chế và những ranh giới cần giữ

Budget gồm network/queue/work/cleanup; propagate remaining deadline. Clocks/transport representation khác nhau nên dùng library deadline propagation.

## Áp dụng vào hệ thống thật

Caller dừng chờ payment provider, chuyển operation sang unknown/pending reconciliation.

## Những đường lỗi cần hiểu

Timeout ngắn tạo duplicate retries; quá dài giữ connections/goroutines; đồng loạt expiry tạo burst.

## Lần theo bằng chứng khi có sự cố

Trace time spent mỗi hop, canceled operations còn chạy và remote outcome records.

## Đánh đổi và giới hạn sử dụng

Timeout nhỏ đổi resource protection lấy false positives; chọn theo SLO và observed tails.

## Thực hành, debugging và kết luận

Quan sát phase latency, queue wait và remote durable record. Tăng timeout chỉ hợp lý khi công việc chậm vẫn có ích và hệ thống chịu được in-flight lớn hơn. Kết hợp admission/concurrency bound để request hết hạn không thành hàng đợi vô hạn.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)
