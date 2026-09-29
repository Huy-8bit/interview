# Vận hành các boundary qua mạng

Khi tách process, local call thành network operation có deadline, retry và unknown outcome. Module ghép communication/discovery với config, secrets, observability và resilience. Đọc để biết chi phí phải nhận khi cần deploy/scale độc lập, không để mặc định mọi domain phải tách thành service.

## Bắt đầu và cách thực hành

Bắt đầu với [service-communication](service-communication.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Configuration lifecycle](configuration.md) | P1 |
| [Distributed transactions và ownership](distributed-transaction.md) | P1 |
| [gRPC service boundaries](grpc-microservices.md) | P1 |
| [Microservice cascading failure](microservice-failure.md) | P1 |
| [Observability across services](observability.md) | P1 |
| [Resilience budget xuyên dependencies](resilience.md) | P1 |
| [Service secrets và rotation](secrets.md) | P1 |
| [Service communication contract](service-communication.md) | P1 |
| [Service discovery và connection lifetime](service-discovery.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
