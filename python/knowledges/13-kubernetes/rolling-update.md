# Rolling Update

> **Phạm vi phỏng vấn:** Kubernetes · **Ưu tiên:** P1/P2 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

Rolling Update là Kubernetes primitive/controller dùng desired state để quản lifecycle, routing hoặc resource của workload.

## 2. Why does it matter?

Senior Engineer cần hiểu **Rolling Update** để vận hành scale, rollout và self-healing mà không che giấu application failure. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

API object lưu desired state; controller reconcile actual state. Hiểu selector/ownership, readiness, scheduling, quota và rollout/failure semantics của primitive.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `pod availability, restart count, saturation, scheduling latency và rollout health` và phân biệt symptom, bottleneck với root cause.

## 4. Example

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: vehicle-api
spec:
  replicas: 3
  selector:
    matchLabels: {app: vehicle-api}
  template:
    metadata:
      labels: {app: vehicle-api}
    spec:
      containers:
        - name: api
          image: registry.example/vehicle-api@sha256:4f9c2f
          resources:
            requests: {cpu: 500m, memory: 512Mi}
            limits: {memory: 1Gi}
```

Manifest minh họa desired state liên quan **Rolling Update**; image digest và resource policy làm rollout có thể kiểm chứng.

## 5. Production Use Case

Vehicle API áp dụng Rolling Update với canary, SLO alert và downstream connection cap; test node/pod termination trước launch.

Checklist triển khai: capacity budget, timeout, idempotency (nếu có side effect), telemetry, canary, rollback và reconciliation.

## 6. Common Problems

- Không định nghĩa invariant và source of truth trước khi chọn công nghệ.
- Retry không backoff/jitter làm traffic amplification khi dependency lỗi.
- Không có bound cho queue, connection, memory hoặc concurrency.
- Chỉ theo dõi average; bỏ qua p95/p99, saturation và error semantics.
- Rollout toàn bộ, thiếu feature flag/canary và đường rollback dữ liệu.

## 7. Trade-offs

| Lựa chọn | Lợi ích | Chi phí / rủi ro | Khi phù hợp |
|---|---|---|---|
| Tối ưu/thiết kế xoay quanh Rolling Update | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is Rolling Update, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind Rolling Update.
- **B3.** Which guarantees does Rolling Update provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of Rolling Update?
- **B5.** What is the most common misconception about Rolling Update?
- **B6.** How would you test assumptions involving Rolling Update?
- **B7.** Which edge cases or failure modes matter most for Rolling Update?
- **B8.** How can Rolling Update affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of Rolling Update?
- **B10.** When is a different or simpler approach better than relying on Rolling Update?

### Production Scenarios (5)

- **S1.** A release involving Rolling Update triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around Rolling Update is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to Rolling Update. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving Rolling Update fails first?
- **S5.** A canary changes the behavior of Rolling Update; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does Rolling Update constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when Rolling Update meets concurrency or partial failure?
- **L3.** What breaks first around Rolling Update at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using Rolling Update?
- **L5.** How would you benchmark or validate Rolling Update without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can Rolling Update introduce?
- **L7.** How would you change a poor decision around Rolling Update with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for Rolling Update?
- **L10.** How would you turn an incident involving Rolling Update into a durable prevention mechanism?

## 10. Short Answers

**B1.** Rolling Update là Kubernetes primitive/controller dùng desired state để quản lifecycle, routing hoặc resource của workload. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của Rolling Update.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo pod availability, restart count, saturation, scheduling latency và rollout health; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng Rolling Update như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh Rolling Update khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của Rolling Update**, không chỉ “dùng để làm gì”.
- Định lượng bằng pod availability, restart count, saturation, scheduling latency và rollout health và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

Hãy xem **Rolling Update** như một boundary biến input/state thành output. Muốn hiểu sâu phải chỉ ra ai sở hữu state, lifecycle, điểm contention và behavior khi dependency chậm hoặc mất.

## 14. Internals Deep Dive

Kubernetes controller reconcile desired state, nhưng application vẫn sở hữu readiness, graceful shutdown, state correctness và downstream capacity. Pod restart không sửa logical corruption.

Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
flowchart TB
            User --> LB --> Ingress --> Service
            Service --> P1["Pod 1"]
            Service --> P2["Pod 2"]
            Controller["Rolling Update controller / object"] -.reconcile.-> P1
            Controller -.reconcile.-> P2
            P1 --> DB[(Downstream)]
            P2 --> DB
```

Đọc diagram từ input tới state transition và output. Tại mỗi mũi tên, hỏi: operation có block không, có retry không, state có durable không, identity nào dùng để dedupe và metric nào chứng minh bước đó khỏe.

## 16. Failure Scenario

Pod healthy không có nghĩa dependency khỏe. Probe sai gây restart storm; HPA scale API có thể connection-storm DB. Cap theo downstream và test graceful drain/zone failure.

Phân tích theo chuỗi: **trigger → saturation/incorrect state → propagation → user impact → immediate mitigation → durable prevention**. Tránh gọi retry hoặc scale là giải pháp nếu chưa chỉ ra dependency budget.

## 17. How I would debug this in production

1. Describe workload/pod và đọc event.
2. Kiểm readiness/endpoints/restart/previous logs.
3. Xem CPU throttling, OOM, request/limit và node pressure.
4. Trace DNS/network/service/downstream.
5. Kiểm rollout diff, HPA metric và graceful termination.

## 18. Common Misconceptions

**Sai:** Kubernetes làm application high availability tự động. **Đúng:** probe, state, dependency và capacity budget sai vẫn tạo outage tự động ở quy mô lớn.

## 19. When NOT to use

Không chọn Kubernetes chỉ để chạy vài service ít thay đổi nếu managed container/serverless đơn giản hơn và team thiếu operational ownership.

## 20. What interviewer may ask next

1. **What guarantee does Rolling Update provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **Rolling Update** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [HPA](hpa.md)
- [Resource Limits](resource-limit.md)
- [Health Checks](health-check.md)
- [Troubleshooting](troubleshooting.md)
