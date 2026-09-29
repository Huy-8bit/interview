# REST versus gRPC

## Bài toán và ví dụ đầu tiên

Một public API phục vụ browser và đối tác có nhu cầu khác traffic service-to-service cùng tổ chức. Chọn REST/JSON hay gRPC dựa client ecosystem, streaming, schema workflow và vận hành, không chỉ benchmark serialization.

## Đi từng bước qua một tình huống

JSON/HTTP dễ inspect và được nhiều công cụ hỗ trợ; gRPC có schema/codegen và streaming theo RPC contract. Một hệ thống có thể dùng public HTTP gateway và gRPC nội bộ, nhưng gateway thêm nơi map status, auth và deadline. Phải kiểm tra mapping không làm mất cause hoặc budget.

## Hiểu cơ chế từ kết quả quan sát

Cả hai vẫn đi qua network có partial failure. HTTP/2 multiplex không bảo đảm downstream nhanh, schema không thay validation, và retry layer không biết semantics payment nếu domain không cung cấp idempotency. Tooling load balancer/proxy và observability cần hiểu protocol dùng thật.

## Khái niệm và mô hình làm việc

So sánh từ client ecosystem, latency, streaming và operational tooling, không từ benchmark hello-world.

## Cơ chế và những ranh giới cần giữ

HTTP JSON dễ inspect/cache/browser; gRPC typed codegen và streaming, cần proxy/load-balancing hiểu HTTP/2 streams.

## Áp dụng vào hệ thống thật

Public REST gateway tới internal gRPC có contract mapping lỗi/deadline rõ.

## Những đường lỗi cần hiểu

Một HTTP/2 connection lâu dài dồn backend khi LB chỉ cân connection; proxy timeout cắt stream.

## Lần theo bằng chứng khi có sự cố

Load test realistic payloads, protocol negotiation, request distribution và generated client compatibility.

## Đánh đổi và giới hạn sử dụng

Không thêm hai protocols nếu team chưa cần; gateway thêm latency và version mapping.

## Thực hành, debugging và kết luận

Thử một endpoint đại diện gồm payload, timeout và lỗi trên client mục tiêu. Đo cả developer workflow và operability, không chỉ bytes. Chọn cách team có thể debug, version và vận hành an toàn ở boundary đó.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9110)

## Thực hành có điều kiện kiểm chứng

So cùng schema/payload, same TLS/network path và business work; report CPU, bytes, allocations, P99 cùng concurrency. Thêm long stream và backend rollout để đánh giá LB distribution/drain, không chỉ unary hello-world. REST có thể dùng HTTP/2, và gRPC không mặc nhiên làm DB nhanh hơn; tách serialization savings khỏi total request critical path.
