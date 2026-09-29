# Probes không phải full diagnostics

## Bài toán và ví dụ đầu tiên

Một dependency Redis tạm lỗi làm liveness fail, Kubernetes restart mọi Pod rồi tạo thêm cache misses. Probe thiết kế sai có thể khuếch đại outage. Liveness, readiness và startup có mục tiêu khác nhau.

## Đi từng bước qua một tình huống

Liveness hỏi process có mắc trạng thái mà restart giúp phục hồi không. Readiness hỏi instance có nên nhận traffic mới không. Startup cho ứng dụng thời gian khởi động trước các kiểm tra phù hợp. Một DB outage chung không luôn nên biến thành restart toàn fleet.

## Hiểu cơ chế từ kết quả quan sát

Probe nên rẻ và có timeout/bound, tránh mỗi probe chạy query đắt. Readiness failure có thể loại endpoint nhưng propagation không tức thì. Nếu mọi replica fail readiness vì dependency chung, traffic vẫn cần policy lỗi rõ thay vì hy vọng scheduler tạo database capacity.

## Khái niệm và mô hình làm việc

Startup, readiness, liveness trả lời ba câu hỏi khác nhau; probe phải rẻ và có bounded latency.

## Cơ chế và những ranh giới cần giữ

Startup trì hoãn liveness/readiness evaluation theo semantics; readiness dừng traffic, liveness restart. Endpoint status phù hợp drain state.

## Áp dụng vào hệ thống thật

Liveness kiểm local progress, readiness check minimum serving capability; dependencies optional không làm toàn pod unready.

## Những đường lỗi cần hiểu

Liveness query DB gây restart storm khi DB outage; threshold quá gắt khi GC/CPU throttle.

## Lần theo bằng chứng khi có sự cố

Probe failure timeline cùng restarts, dependency errors và CPU; test slow startup.

## Đánh đổi và giới hạn sử dụng

Probe sâu tăng coverage nhưng thêm cascading dependency; synthetic end-to-end checks tách riêng.

## Thực hành, debugging và kết luận

Test dependency down và startup chậm để xem có restart loop không. Đo probe failures cùng restart count và resource use. Chọn điều kiện theo khả năng phục vụ thật, không chỉ luôn200 hoặc ping mọi dependency không phân loại.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
