# Docker Kubernetes

Nối Go runtime budgets với container/platform lifecycle.

## Reading map

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

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
