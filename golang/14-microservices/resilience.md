# Resilience budget xuyên dependencies

## Bài toán và ví dụ đầu tiên

Một dependency chậm có thể giữ hết goroutine/pool khiến service không trả được cả endpoint không liên quan. Resilience là thiết kế cách hệ thống giữ hành vi có ích và phục hồi dưới failure đã xác định.

## Đi từng bước qua một tình huống

Timeout giới hạn chờ, retry có budget thử lỗi tạm thời, breaker fail-fast khi partner lỗi, bulkhead tách capacity và load shedding từ chối work vượt khả năng. Các cơ chế bổ sung nhau; bật retry mà thiếu bound có thể làm failure nặng hơn.

## Hiểu cơ chế từ kết quả quan sát

Fallback phải được product chấp nhận: trả recommendation cũ có thể được, giả vờ payment thành công thì không. Circuit breaker state cần recovery probes; queue cần max age và durable policy. Unknown mutation outcome cần idempotency/reconcile chứ không chỉ bắt error.

## Khái niệm và mô hình làm việc

Timeout, retry, circuit breaker và bulkhead phải phối hợp theo total capacity/deadline.

## Cơ chế và những ranh giới cần giữ

Bound concurrency trước retry; classify errors; fallbacks có correctness/freshness contract. Per-dependency budget bảo vệ critical path.

## Áp dụng vào hệ thống thật

Recommendations fail có thể omit; authorization fail thường reject thay allow.

## Những đường lỗi cần hiểu

Fallback cũng gọi dependency đang lỗi; retry storm; circuit global làm unrelated routes outage.

## Lần theo bằng chứng khi có sự cố

Chaos test một dependency chậm/down và đo blast radius, not just success on happy path.

## Đánh đổi và giới hạn sử dụng

Mỗi mechanism thêm state/complexity; bắt đầu từ deadline+limits+idempotency.

## Thực hành, debugging và kết luận

Fault-inject một dependency chậm, kiểm tra endpoint khác còn SLO và memory không tăng vô hạn. Đo retry amplification, queue age và rejected work. Complexity của resilience cũng có lỗi; dùng cơ chế tối thiểu có contract và telemetry đủ để kiểm chứng.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)

## Thực hành có điều kiện kiểm chứng

Viết matrix theo dependency: recommendations optional→omit; inventory authority→reject mutation nếu unknown; cache catalog→bounded stale; telemetry exporter→bounded drop. Cùng timeout không thể áp cùng fallback cho mọi dependency. Test optional outage không làm critical endpoint exhaust shared pools. Mỗi fallback cần metric để degraded mode không ẩn kéo dài.
