# Service discovery và connection lifetime

## Bài toán và ví dụ đầu tiên

Replica IP thay đổi khi deploy hoặc autoscale. Caller cần tìm endpoint đang phục vụ mà không hardcode một IP trong binary. Service discovery cung cấp thông tin endpoint, qua DNS, registry hoặc nền tảng orchestration.

## Đi từng bước qua một tình huống

Caller resolve service name tới địa chỉ rồi connection pool có thể giữ connection lâu. DNS cập nhật không nhất thiết chuyển ngay mọi traffic vì connection cũ còn sống. Khi endpoint rời đi, cần readiness/drain và client xử lý failure/reconnect đúng budget.

## Hiểu cơ chế từ kết quả quan sát

Discovery nói endpoint ở đâu, không bảo đảm request hiện tại sẽ thành công hoặc user có quyền. Cache TTL, health signals và propagation delay làm danh sách có thể stale. Load balancing có thể nằm ở client hoặc proxy, mỗi cách có visibility/failure mode riêng.

## Khái niệm và mô hình làm việc

Discovery ánh xạ service identity tới endpoints; stale endpoints tồn tại trong caches và long-lived connections.

## Cơ chế và những ranh giới cần giữ

DNS, platform service routing hoặc client resolver có update/TTL/load-balance policies. HTTP/2 gRPC connection reuse ảnh hưởng distribution.

## Áp dụng vào hệ thống thật

Kubernetes Service tới pods, readiness loại endpoints theo propagation delay.

## Những đường lỗi cần hiểu

DNS cache stale, connection pin vào một pod, headless service client không rebalance.

## Lần theo bằng chứng khi có sự cố

Resolve answers/TTLs, endpoint health, per-pod traffic và client connection age.

## Đánh đổi và giới hạn sử dụng

Client-side LB thêm logic; server-side proxy thêm hop và operational surface.

## Thực hành, debugging và kết luận

Khi traffic lệch sau rollout, đối chiếu resolved endpoints, active connections và readiness timeline. Test endpoint removal với keep-alive. Tránh retry storm khi registry/DNS lỗi; đặt timeout, dùng connection reuse có chủ đích và quan sát resolver errors.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)

## Thực hành có điều kiện kiểm chứng

Trong rollout, endpoint removal và client connection reuse xảy ra ở thời điểm khác nhau. Server cần drain in-flight, client cần reconnect/retry policy replay-safe khi connection đóng. DNS TTL giảm không tự đóng socket đã mở. Test backend replacement với active streams và observe traffic migration, errors và reconnect burst trước thay discovery architecture.
