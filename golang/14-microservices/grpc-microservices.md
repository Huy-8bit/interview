# gRPC service boundaries

## Bài toán và ví dụ đầu tiên

Một fleet Go services dùng gRPC để có schema và codegen. Stub gọi method trông như local function, nhưng thực tế có network, connection/stream limits và remote failure. Cần giữ sự khác biệt này trong contract.

## Đi từng bước qua một tình huống

Caller tạo RPC với deadline tổng còn lại, server truyền context tới DB/HTTP. Retry ở interceptor phải biết method nào an toàn, tránh mutation không idempotent. Streaming cần owner send/receive và đường close/cancel để goroutine không chờ vô hạn.

## Hiểu cơ chế từ kết quả quan sát

Load balancing và connection reuse phụ thuộc client resolver/proxy/config thực tế. Một long-lived connection có thể phân tải khác HTTP requests rời nếu infrastructure không hiểu HTTP/2/gRPC. Status mapping phải giữ validation, unavailable và deadline khác nhau theo contract.

## Khái niệm và mô hình làm việc

Reuse ClientConn và generated clients; deadline/metadata/status là phần API contract.

## Cơ chế và những ranh giới cần giữ

Unary/stream interceptors auth/trace, bounded message size và stream concurrency; validate metadata chỉ từ trusted identity.

## Áp dụng vào hệ thống thật

Internal inventory RPC có per-call deadline và resource-specific authorization.

## Những đường lỗi cần hiểu

Stream không CloseSend/receive completion, context bị bỏ, retry partial stream thiếu resume protocol.

## Lần theo bằng chứng khi có sự cố

RPC method/status metrics, active streams, flow-control waits và load distribution.

## Đánh đổi và giới hạn sử dụng

Không assume HTTP/2 làm mọi load balancer aware; kiểm tra proxy settings.

## Thực hành, debugging và kết luận

Integration test qua transport với version schema cũ/mới, cancellation và message size. Đo per-method latency, active streams và reconnects. Không công khai reflection/admin endpoint tùy ý ngoài trust boundary; auth/authorization vẫn cần ở từng resource operation.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)

## Thực hành có điều kiện kiểm chứng

Test unary deadline với server chờ ctx.Done và verify goroutine hoàn tất. Với streaming, cố ý consumer chậm để observe Send block/flow control, rồi cancel và join sender. ClientConn reuse không đồng nghĩa một logical call không cần timeout. Metadata inbound không tự trusted: validate caller identity và allowlist forward fields trước call sang service tiếp theo.
