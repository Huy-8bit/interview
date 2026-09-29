# Bulkheads và capacity isolation

## Bài toán và ví dụ đầu tiên

Dịch vụ có hai downstream: profile và recommendation. Recommendation chậm giữ hết worker chung, làm profile cũng timeout dù nó còn khỏe. Bulkhead chia capacity để lỗi của một nhóm không dùng hết tài nguyên của nhóm khác.

## Đi từng bước qua một tình huống

Tạo giới hạn in-flight riêng cho từng dependency hoặc nhóm tenant có policy. Khi recommendation hết slot, trả phần thiếu hoặc lỗi theo contract thay vì giữ worker cần cho profile. Số slot không nhất thiết chia đều; bắt đầu từ nhu cầu và capacity measured.

## Hiểu cơ chế từ kết quả quan sát

Tách connection pool mà vẫn dùng chung một unbounded queue có thể chưa đủ. Xem toàn đường tài nguyên: goroutine, memory payload, CPU và DB. Nếu fallback của dependency A lại dồn tất cả sang B, cần kiểm tra B có budget chịu được traffic failover không.

## Khái niệm và mô hình làm việc

Bulkhead chia capacity để một dependency/tenant failure không làm cạn tài nguyên mọi request.

## Cơ chế và những ranh giới cần giữ

Separate semaphores, worker pools, queue quotas và client/DB budgets theo failure domain; giữ reserve cho critical path.

## Áp dụng vào hệ thống thật

Report export workers không chiếm toàn DB pool của checkout.

## Những đường lỗi cần hiểu

Tách HTTP clients nhưng vẫn chung unbounded goroutines/DB nên isolation giả.

## Lần theo bằng chứng khi có sự cố

Per-class queue/active/reject metrics và failure injection một dependency.

## Đánh đổi và giới hạn sử dụng

Isolation giảm sharing efficiency; nhiều pools tăng aggregate connections.

## Thực hành, debugging và kết luận

Quan sát wait/reject per dependency và chạy failure injection chỉ một downstream. Kết quả mong đợi là phần còn lại giữ SLO. Bulkhead có thể để một số capacity nhàn khi nhóm khác quá tải; đó là chi phí isolation cần cân bằng với fairness và hiệu suất.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)

## Thực hành có điều kiện kiểm chứng

Giả định DB budget100 slots: checkout60, reports20, workers10, reserve10. Khi reports chậm, checkout không được dùng chung unbounded acquisition queue khiến isolation mất ý nghĩa. Static partition có thể lãng phí khi reports idle; adaptive borrowing cần reserve floor và overload tests. Budget còn phải nhân theo replicas hoặc dùng central authority tương ứng.
