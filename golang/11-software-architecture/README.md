# Tổ chức code theo trách nhiệm và dependency

Bắt đầu một use case thật: handler nhận dữ liệu, service giữ rule, repository thực hiện I/O. Các mô hình kiến trúc giúp giữ những phần thay đổi khác nhau ở boundary rõ; chúng không yêu cầu tạo interface/layer cho mọi struct. So sánh modular monolith và microservices sau khi thấy transaction/failure boundary.

## Bắt đầu và cách thực hành

Bắt đầu với [go-project-structure](go-project-structure.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Clean Architecture theo tinh thần Go](clean-architecture.md) | P1 |
| [Explicit dependency injection](dependency-injection.md) | P1 |
| [DDD: invariants và bounded contexts](domain-driven-design.md) | P1 |
| [Go project structure không có một luật duy nhất](go-project-structure.md) | P1 |
| [Ports và adapters](hexagonal-architecture.md) | P1 |
| [Layered architecture và vertical features](layered-architecture.md) | P1 |
| [Microservices: independent ownership có chi phí](microservices.md) | P1 |
| [Modular monolith](modular-monolith.md) | P1 |
| [Repository theo use case](repository-pattern.md) | P1 |
| [Service giữ business orchestration](service-pattern.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
