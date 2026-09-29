# Volume

> **Phạm vi phỏng vấn:** Docker · **Ưu tiên:** P1/P2 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

Volume là cơ chế build/runtime của container, ảnh hưởng reproducibility, isolation, startup và supply-chain security.

## 2. Why does it matter?

Senior Engineer cần hiểu **Volume** để đóng gói ứng dụng nhất quán và giảm supply-chain risk. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Image tạo từ immutable layer; runtime thêm writable layer/namespaces/cgroups. Pin dependency/digest, chạy non-root, externalize state và xử lý SIGTERM.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `image size, build time, startup time, CVE count và resource use` và phân biệt symptom, bottleneck với root cause.

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

Manifest minh họa desired state liên quan **Volume**; image digest và resource policy làm rollout có thể kiểm chứng.

## 5. Production Use Case

Python service dùng Volume để build một artifact nhất quán; CI scan/SBOM/sign và production kiểm tra startup/resource trước promote.

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
| Tối ưu/thiết kế xoay quanh Volume | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is Volume, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind Volume.
- **B3.** Which guarantees does Volume provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of Volume?
- **B5.** What is the most common misconception about Volume?
- **B6.** How would you test assumptions involving Volume?
- **B7.** Which edge cases or failure modes matter most for Volume?
- **B8.** How can Volume affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of Volume?
- **B10.** When is a different or simpler approach better than relying on Volume?

### Production Scenarios (5)

- **S1.** A release involving Volume triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around Volume is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to Volume. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving Volume fails first?
- **S5.** A canary changes the behavior of Volume; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does Volume constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when Volume meets concurrency or partial failure?
- **L3.** What breaks first around Volume at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using Volume?
- **L5.** How would you benchmark or validate Volume without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can Volume introduce?
- **L7.** How would you change a poor decision around Volume with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for Volume?
- **L10.** How would you turn an incident involving Volume into a durable prevention mechanism?

## 10. Short Answers

**B1.** Volume là cơ chế build/runtime của container, ảnh hưởng reproducibility, isolation, startup và supply-chain security. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của Volume.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo image size, build time, startup time, CVE count và resource use; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng Volume như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh Volume khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của Volume**, không chỉ “dùng để làm gì”.
- Định lượng bằng image size, build time, startup time, CVE count và resource use và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.
