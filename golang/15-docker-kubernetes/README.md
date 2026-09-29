# Nối Go lifecycle với container và deployment

Binary chạy trong resource limits và lifecycle của nền tảng. Đi từ image/container tới Service/Ingress/probes, rồi HPA và graceful deployment. CPU quota, memory headroom và propagation delay giúp giải thích vì sao tăng replicas hoặc readiness flag không tự tạo capacity hay dừng mọi traffic tức thì.

## Bắt đầu và cách thực hành

Bắt đầu với [containers](containers.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Container resources và process model](containers.md) | P1 |
| [Deployment và rollout capacity](deployment.md) | P1 |
| [Docker cho Go services](docker-for-go.md) | P1 |
| [Graceful deployment và SIGTERM budget](graceful-deployment.md) | P1 |
| [HPA và scaling limits](hpa.md) | P1 |
| [Ingress và proxy boundary](ingress.md) | P1 |
| [Kubernetes mental model](kubernetes.md) | P1 |
| [Multi-stage builds](multistage-build.md) | P1 |
| [Probes không phải full diagnostics](probes.md) | P1 |
| [Resource requests, limits và Go budgets](resource-limits.md) | P1 |
| [Kubernetes Service và endpoint routing](service.md) | P1 |
| [Static binaries và cgo](static-binary.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
