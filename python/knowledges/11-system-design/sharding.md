# Sharding

> **Phạm vi phỏng vấn:** System Design · **Ưu tiên:** P1/P2 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

Sharding là một building block dùng để đáp ứng throughput, latency, durability hoặc operability trong thiết kế hệ thống.

## 2. Why does it matter?

Senior Engineer cần hiểu **Sharding** để biến requirement mơ hồ thành kiến trúc có thể scale và vận hành. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Bắt đầu từ requirement/con số, đặt component trên read/write path, xác định state/ownership rồi phân tích saturation, failure propagation và recovery.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `throughput, latency, availability, durability, cost và recovery time` và phân biệt symptom, bottleneck với root cause.

## 4. Example

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Decision:
    topic: str
    invariant: str
    metric: str

decision = Decision(
    topic='Sharding',
    invariant="Không làm mất hoặc lặp business effect",
    metric="p99 latency và error rate",
)
```

Ví dụ biến quyết định về **Sharding** thành invariant và tín hiệu vận hành có thể kiểm chứng.

## 5. Production Use Case

Kiến trúc automotive áp dụng Sharding sau capacity test; rollout theo cell/canary và theo dõi SLO/cost trước khi mở rộng.

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
| Tối ưu/thiết kế xoay quanh Sharding | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is Sharding, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind Sharding.
- **B3.** Which guarantees does Sharding provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of Sharding?
- **B5.** What is the most common misconception about Sharding?
- **B6.** How would you test assumptions involving Sharding?
- **B7.** Which edge cases or failure modes matter most for Sharding?
- **B8.** How can Sharding affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of Sharding?
- **B10.** When is a different or simpler approach better than relying on Sharding?

### Production Scenarios (5)

- **S1.** A release involving Sharding triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around Sharding is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to Sharding. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving Sharding fails first?
- **S5.** A canary changes the behavior of Sharding; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does Sharding constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when Sharding meets concurrency or partial failure?
- **L3.** What breaks first around Sharding at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using Sharding?
- **L5.** How would you benchmark or validate Sharding without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can Sharding introduce?
- **L7.** How would you change a poor decision around Sharding with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for Sharding?
- **L10.** How would you turn an incident involving Sharding into a durable prevention mechanism?

## 10. Short Answers

**B1.** Sharding là một building block dùng để đáp ứng throughput, latency, durability hoặc operability trong thiết kế hệ thống. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của Sharding.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo throughput, latency, availability, durability, cost và recovery time; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng Sharding như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh Sharding khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của Sharding**, không chỉ “dùng để làm gì”.
- Định lượng bằng throughput, latency, availability, durability, cost và recovery time và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

Hãy xem **Sharding** như một boundary biến input/state thành output. Muốn hiểu sâu phải chỉ ra ai sở hữu state, lifecycle, điểm contention và behavior khi dependency chậm hoặc mất.

## 14. Internals Deep Dive

Bắt đầu từ workload model và invariant. Vẽ read/write critical path, source of truth và asynchronous projection; sau đó mới thêm cache/queue/shard theo bottleneck đã định lượng.

Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
flowchart LR
            Requirement --> Estimate
            Estimate --> Simple["Simple Sharding design"]
            Simple --> Measure["Measure bottleneck"]
            Measure --> Scale["Add capacity / partition / queue"]
            Scale --> Operate["SLO + failure recovery"]
```

Đọc diagram từ input tới state transition và output. Tại mỗi mũi tên, hỏi: operation có block không, có retry không, state có durable không, identity nào dùng để dedupe và metric nào chứng minh bước đó khỏe.

## 16. Failure Scenario

Một tier scale nhanh có thể overload tier stateful. Mỗi design cần degraded mode, global capacity budget, backpressure, multi-AZ restore test và per-tenant isolation.

Phân tích theo chuỗi: **trigger → saturation/incorrect state → propagation → user impact → immediate mitigation → durable prevention**. Tránh gọi retry hoặc scale là giải pháp nếu chưa chỉ ra dependency budget.

## 17. How I would debug this in production

1. Xác nhận user-visible SLI và blast radius.
2. Trace critical read/write path.
3. Xem saturation: worker, pool, DB, cache, queue, provider.
4. Tìm hot tenant/key/partition và retry amplification.
5. Kích hoạt degraded mode/rollback.
6. Cập nhật capacity model và failure test.

## 18. Common Misconceptions

**Sai:** diagram nhiều service là senior design. **Đúng:** design senior giải thích requirement, số liệu, source of truth, failure và lý do từng component xuất hiện.

## 19. When NOT to use

Ở 100 RPS, tránh Kafka, sharding và nhiều microservice nếu 2 API instance + PostgreSQL đáp ứng SLO và recovery.

## 20. What interviewer may ask next

1. **What guarantee does Sharding provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **Sharding** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [Design Framework](system-design-framework.md)
- [Capacity Estimation](capacity-estimation.md)
- [Observability](observability.md)
- [Production Scenarios](../20-senior-scenarios/README.md)
