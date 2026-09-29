# Load balancing: connection versus request

## Bài toán và ví dụ đầu tiên

Nhiều API replicas chỉ hữu ích nếu traffic được phân phối và endpoint lỗi được loại theo policy. Load balancer chọn backend, nhưng long-lived connections, hot clients và request cost khác nhau làm phân tải không chỉ là chia request count đều.

## Đi từng bước qua một tình huống

Round-robin đơn giản, least-connections hoặc policy khác có assumptions về cost. Với HTTP/2 một connection có nhiều streams nên connection count không phản ánh chính xác work. Sticky sessions giúp state local nhưng làm failover/skew phức tạp; stateless APIs thường dễ scale hơn.

## Hiểu cơ chế từ kết quả quan sát

Health signals có delay và existing connections có lifecycle riêng. Retry ở LB có thể duplicate mutation nếu upstream đã commit trước reset; cần contract idempotency. Cross-zone routing đổi availability, latency và chi phí network.

## Khái niệm và mô hình làm việc

LB phân phối traffic theo level/policy; multiplexed connections làm connection balance khác request balance.

## Cơ chế và những ranh giới cần giữ

L4 route TCP flows, L7 hiểu HTTP/RPC; health/readiness update có delay. Least-load policies cần accurate in-flight metrics.

## Áp dụng vào hệ thống thật

Long-lived gRPC/WebSocket cần scale/drain strategy và reconnect/resume.

## Những đường lỗi cần hiểu

Sticky hot tenant, endpoint stale, connection reuse pin backend, cross-zone overload.

## Lần theo bằng chứng khi có sự cố

Per-backend RPS/in-flight/latency, connection age và health transitions.

## Đánh đổi và giới hạn sử dụng

L7 thêm hop/CPU và config complexity; L4 đơn giản nhưng ít visibility request.

## Thực hành, debugging và kết luận

Đo per-replica completed rate, CPU, active operations và P99. Test backend removal và slow endpoint chứ không chỉ kill process. Thêm replicas không giúp DB chung bão hòa; load balancing phân việc chứ không tạo downstream capacity.


## Đọc tiếp

- [System design framework cho Senior Go](system-design-framework.md)
- [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md)
- [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)

## Thực hành có điều kiện kiểm chứng

Lab giữ10 long-lived HTTP/2 connections tới2 pods rồi scale lên4. Nếu LB chỉ route lúc connect, new pods có thể ít traffic cho tới reconnect. Đo request distribution và active streams theo pod; không kết luận HPA hỏng chỉ vì CPU skew. Graceful drain cần connection/stream termination policy để redistribute mà giữ client resume/retry safety.
