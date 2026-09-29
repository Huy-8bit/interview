# CI/CD

> **Phạm vi phỏng vấn:** Terraform & CI/CD · **Ưu tiên:** P1/P2 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

CI/CD là mechanism của infrastructure/delivery workflow để thay đổi có thể review, lặp lại và phục hồi.

## 2. Why does it matter?

Senior Engineer cần hiểu **CI/CD** để tạo thay đổi lặp lại được, review được và rollback có kiểm soát. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Desired configuration được plan/diff rồi apply qua state/runner có lock; pipeline tạo immutable artifact, gate bằng test/policy và promote cùng artifact.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `deployment frequency, lead time, drift, failure rate và MTTR` và phân biệt symptom, bottleneck với root cause.

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

Manifest minh họa desired state liên quan **CI/CD**; image digest và resource policy làm rollout có thể kiểm chứng.

## 5. Production Use Case

Platform team áp dụng CI/CD với remote state, least-privilege runner, canary và automated rollback dựa trên SLO burn.

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
| Tối ưu/thiết kế xoay quanh CI/CD | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is CI/CD, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind CI/CD.
- **B3.** Which guarantees does CI/CD provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of CI/CD?
- **B5.** What is the most common misconception about CI/CD?
- **B6.** How would you test assumptions involving CI/CD?
- **B7.** Which edge cases or failure modes matter most for CI/CD?
- **B8.** How can CI/CD affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of CI/CD?
- **B10.** When is a different or simpler approach better than relying on CI/CD?

### Production Scenarios (5)

- **S1.** A release involving CI/CD triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around CI/CD is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to CI/CD. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving CI/CD fails first?
- **S5.** A canary changes the behavior of CI/CD; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does CI/CD constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when CI/CD meets concurrency or partial failure?
- **L3.** What breaks first around CI/CD at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using CI/CD?
- **L5.** How would you benchmark or validate CI/CD without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can CI/CD introduce?
- **L7.** How would you change a poor decision around CI/CD with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for CI/CD?
- **L10.** How would you turn an incident involving CI/CD into a durable prevention mechanism?

## 10. Short Answers

**B1.** CI/CD là mechanism của infrastructure/delivery workflow để thay đổi có thể review, lặp lại và phục hồi. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của CI/CD.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo deployment frequency, lead time, drift, failure rate và MTTR; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng CI/CD như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh CI/CD khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của CI/CD**, không chỉ “dùng để làm gì”.
- Định lượng bằng deployment frequency, lead time, drift, failure rate và MTTR và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.
