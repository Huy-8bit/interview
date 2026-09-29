# Microservice cascading failure

## Bài toán và ví dụ đầu tiên

Inventory tăng latency từ 30 ms lên 2 giây. Orders fan-out và retry làm số call in-flight tăng, pool đầy rồi gateway cũng timeout. Một lỗi dependency nhỏ trở thành cascade khi các tầng giữ tài nguyên và khuếch đại work.

## Đi từng bước qua một tình huống

Vẽ timeline dependency chậm→requests tồn tại lâu→queue/pool đầy→timeouts→retries. Mitigation có thể là giảm admission, tắt optional calls và giới hạn retries, không chỉ restart mọi pod. Restart đồng loạt còn tạo cold pools/caches và mất bằng chứng.

## Hiểu cơ chế từ kết quả quan sát

Bulkhead ngăn một dependency giữ toàn capacity; deadline giới hạn lifetime; breaker giảm calls thất bại lặp. Tuy nhiên data side effects đã commit vẫn cần reconcile. Service healthy trở lại không tự xử lý backlog hoặc duplicates mà outage đã tạo.

## Khái niệm và mô hình làm việc

Một dependency chậm có thể làm callers giữ pools/G/memory rồi lan thành outage.

## Cơ chế và những ranh giới cần giữ

Bound waits/concurrency và isolate pools; stop retries khi budget hết; reject overload trước khi chạm OOM.

## Áp dụng vào hệ thống thật

DB slowdown khiến API shed optional work và stop background backfill.

## Những đường lỗi cần hiểu

Autoscale app tăng connections vào DB đang saturate; liveness phụ thuộc DB làm restart storm.

## Lần theo bằng chứng khi có sự cố

Timeline latency, in-flight, pool wait, errors và restarts; xác định dependency đầu tiên lệch baseline.

## Đánh đổi và giới hạn sử dụng

Availability local không đủ; dependency capacity giới hạn toàn path.

## Thực hành, debugging và kết luận

Theo dõi completion rate và oldest pending operations trong recovery. Lấy profiles/traces có phạm vi trước mitigation khi khả thi. Postmortem cần chứng minh trigger, amplification và recovery gaps bằng timeline, rồi test bản sửa với dependency failure tương ứng.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)

## Thực hành có điều kiện kiểm chứng

Fault injection làm inventory delay2s trong khi order budget200 ms. Order phải fail/degrade trong budget, không giữ goroutines tăng vô hạn và không retry tầng tầng. Observe breaker/semaphore state, DB pool và remaining capacity của payment path. Sau dependency hồi phục, bounded half-open probes và jitter tránh recovery herd; verify queued work đã reconcile.
