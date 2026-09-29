# Api Design

Thiết kế API contracts, compatibility và trust boundaries.

## Reading map

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

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
