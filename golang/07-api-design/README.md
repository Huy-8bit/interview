# Contract giữa backend và client

Một API phải diễn đạt kết quả, lỗi, quyền truy cập, pagination và retry an toàn để client phục hồi được khi mạng lỗi. Học HTTP/gRPC/schema theo tình huống client thực, rồi xem identity, quota và compatibility. Type-safe payload không thay semantics của mutation hoặc authorization trên resource.

## Bắt đầu và cách thực hành

Bắt đầu với [rest-api](rest-api.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [API security theo trust boundaries](api-security.md) | P1 |
| [Authentication và authorization](authentication.md) | P1 |
| [gRPC: transport và call shapes](grpc.md) | P1 |
| [API idempotency key](idempotency.md) | P1 |
| [Pagination: stable order và cursor](pagination.md) | P1 |
| [Protobuf và schema evolution](protobuf.md) | P1 |
| [API rate limiting](rate-limiting.md) | P1 |
| [REST API contracts](rest-api.md) | P1 |
| [REST versus gRPC](rest-vs-grpc.md) | P1 |
| [API retry và deadline](retry-timeout.md) | P1 |
| [API versioning và compatibility](versioning.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
