# Kubernetes mental model

## Bài toán và ví dụ đầu tiên

Một process đơn lẻ có thể chết hoặc cần nhiều replica. Kubernetes quản lý desired state cho workloads, scheduling và service routing; ứng dụng vẫn chịu trách nhiệm dữ liệu, idempotency và graceful shutdown.

## Đi từng bước qua một tình huống

Deployment khai báo số replicas/image; Pods là instance chạy containers; Service cung cấp endpoint ổn định tới tập Pods theo selectors. Readiness quyết định Pod đủ điều kiện nhận traffic, liveness quyết định khi nào restart có thể cần. Chúng giải quyết các lớp khác nhau.

## Hiểu cơ chế từ kết quả quan sát

Control loops hội tụ theo thời gian, không cập nhật mọi proxy/endpoint tức thì. Requests/limits ảnh hưởng scheduling và tài nguyên, HPA thay replica count dựa metrics. Thêm replicas cũng nhân connection pools và downstream concurrency nên application/fleet budget phải đi cùng.

## Khái niệm và mô hình làm việc

Kubernetes controllers reconcile desired state qua API; scheduling/restarts không hiểu application correctness.

## Cơ chế và những ranh giới cần giữ

Pod là scheduling unit; Deployment quản replicas/rollout; Service route tới endpoints; probes/resource requests/limits ảnh hưởng availability.

## Áp dụng vào hệ thống thật

Stateless Go API replicas, durable state ngoài pod; workers cần idempotency qua restarts.

## Những đường lỗi cần hiểu

Assume restart là recovery đủ; local in-memory accepted jobs mất khi pod rescheduled.

## Lần theo bằng chứng khi có sự cố

Events, pod status/restart reason, rollout history, endpoints và application SLO.

## Đánh đổi và giới hạn sử dụng

Kubernetes thêm orchestration cost; không bắt buộc cho service nhỏ nếu platform khác đủ.

## Thực hành, debugging và kết luận

Test rollout với traffic đang chạy và dependency chậm. Đọc events, pod termination reason và throttling/OOM trước khi đổ lỗi GC. Kubernetes khởi động lại process không đối soát một payment đã commit mà response bị mất; domain recovery vẫn cần durable state.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)

## Thực hành có điều kiện kiểm chứng

Triển khai một Go pod với startup/readiness/liveness riêng rồi inject slow DB. Nếu liveness phụ thuộc DB, toàn fleet có thể restart làm pool/TLS warm-up nặng hơn. Sửa liveness theo local progress, giữ readiness/degraded policy phù hợp user contract. Kubernetes giữ desired replica count, còn durable accepted jobs và replay correctness vẫn là trách nhiệm application.
