# Kubernetes Service và endpoint routing

## Bài toán và ví dụ đầu tiên

Pods thay IP sau restart nên caller không nên hardcode Pod IP. Kubernetes Service tạo một abstraction endpoint ổn định và lựa chọn backend theo selectors/endpoints của cluster.

## Đi từng bước qua một tình huống

Khi Pod chưa ready, nó có thể bị loại khỏi tập backend theo cơ chế nền tảng; existing connections vẫn có lifecycle riêng. Long-lived HTTP/2/gRPC connection có thể giữ traffic vào một backend lâu hơn người vận hành nghĩ khi chỉ nhìn số Pods.

## Hiểu cơ chế từ kết quả quan sát

Service discovery/routing không kiểm tra authorization nghiệp vụ và không đảm bảo dependency khỏe tại thời điểm request. Network policy, DNS và proxy/dataplane config ảnh hưởng đường đi. Headless service có semantics discovery khác virtual IP service, cần chọn theo client/load-balancing model.

## Khái niệm và mô hình làm việc

Service tạo stable discovery/routing tới matching endpoints; không quản business request load trực tiếp.

## Cơ chế và những ranh giới cần giữ

Selectors/EndpointSlices quyết định targets; readiness ảnh hưởng endpoints theo propagation. Headless service trả endpoints cho client xử lý.

## Áp dụng vào hệ thống thật

Internal Go API dùng DNS service name; gRPC client hiểu connection lifecycle/load distribution.

## Những đường lỗi cần hiểu

Selector sai không endpoints; session affinity làm hot pods; stale long-lived connections.

## Lần theo bằng chứng khi có sự cố

kubectl get service/endpointslices, DNS resolution và per-pod request rates.

## Đánh đổi và giới hạn sử dụng

L4 connection balancing không tương đương L7 request balancing với multiplexing.

## Thực hành, debugging và kết luận

Khi traffic không tới Pod, kiểm tra selectors/endpoints, readiness và port mapping trước code handler. Test scale/down với keep-alive. Đo per-replica requests để phát hiện imbalance do connections dài hạn thay vì tăng replicas vô thức.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)

## Thực hành có điều kiện kiểm chứng

Chẩn đoán Service không nhận traffic theo thứ tự: selector match pods, endpoints ready, targetPort/listener binding, network policy, rồi DNS/client caching. Go server chỉ bind127.0.0.1 sẽ không nhận traffic tới pod IP; lab server trong examples cố ý local-only, deployment thật cần explicit bind policy. Không sửa app logic trước kiểm routing path.
