# Kubernetes

Module này được học theo **Why → How → Internals → Flow → Failure → Trade-off → Production**. Không đọc alphabet; đi theo dependency dưới đây và tự vẽ lại diagram trước khi xem.

## Learning order

[Architecture](architecture.md) → [Resource Limit](resource-limit.md) → [Health Check](health-check.md) → [Horizontal Pod Autoscaler (HPA)](hpa.md) → [Rolling Update](rolling-update.md) → [Troubleshooting](troubleshooting.md)

## Must know

- [Architecture](architecture.md)
- [Resource Limit](resource-limit.md)
- [Health Check](health-check.md)
- [Horizontal Pod Autoscaler (HPA)](hpa.md)
- [Rolling Update](rolling-update.md)
- [Troubleshooting](troubleshooting.md)

## Nice to know / second pass

- [Pod](pod.md)
- [Deployment](deployment.md)
- [Service](service.md)
- [Ingress](ingress.md)
- [Configmap Secret](configmap-secret.md)
- [Scheduling](scheduling.md)

## Recommended exercises

1. Giải thích mỗi Must-know topic trong 2 phút, không nhìn note; interviewer hỏi “why?” ít nhất ba lần.
2. Vẽ request/data/failure flow từ trí nhớ và đánh dấu source of truth, queue, timeout, retry, metric.
3. Chọn một production incident liên quan **Kubernetes**, trình bày mitigation trước root cause và long-term prevention.
4. Load/fault test một assumption: bottleneck, duplicate, stale state hoặc dependency outage.

## All topics

- [Architecture](architecture.md)
- [Pod](pod.md)
- [Deployment](deployment.md)
- [Service](service.md)
- [Ingress](ingress.md)
- [Configmap Secret](configmap-secret.md)
- [Horizontal Pod Autoscaler (HPA)](hpa.md)
- [Resource Limit](resource-limit.md)
- [Health Check](health-check.md)
- [Rolling Update](rolling-update.md)
- [Scheduling](scheduling.md)
- [Troubleshooting](troubleshooting.md)

[← Main Dashboard](../README.md)
