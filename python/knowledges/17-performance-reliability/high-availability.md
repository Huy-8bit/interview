# High Availability

> **Phạm vi phỏng vấn:** Performance & Reliability · **Ưu tiên:** P1/P2 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

High Availability là phương pháp đo hoặc kiểm soát latency, capacity và failure để giữ user journey trong SLO.

## 2. Why does it matter?

Senior Engineer cần hiểu **High Availability** để tối ưu dựa trên evidence và giữ user journey trong SLO khi có failure. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Thiết lập SLI/baseline, phân rã critical path/queueing/saturation, tạo hypothesis rồi profile/load/fault test; optimization phải so trước-sau.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `SLI, error budget, saturation, p99 latency, MTTR và cost per request` và phân biệt symptom, bottleneck với root cause.

## 4. Example

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Decision:
    topic: str
    invariant: str
    metric: str

decision = Decision(
    topic='High Availability',
    invariant="Không làm mất hoặc lặp business effect",
    metric="p99 latency và error rate",
)
```

Ví dụ biến quyết định về **High Availability** thành invariant và tín hiệu vận hành có thể kiểm chứng.

## 5. Production Use Case

API production áp dụng High Availability trong canary và incident; error-budget/burn-rate điều khiển rollout và backlog reliability.

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
| Tối ưu/thiết kế xoay quanh High Availability | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is High Availability, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind High Availability.
- **B3.** Which guarantees does High Availability provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of High Availability?
- **B5.** What is the most common misconception about High Availability?
- **B6.** How would you test assumptions involving High Availability?
- **B7.** Which edge cases or failure modes matter most for High Availability?
- **B8.** How can High Availability affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of High Availability?
- **B10.** When is a different or simpler approach better than relying on High Availability?

### Production Scenarios (5)

- **S1.** A release involving High Availability triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around High Availability is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to High Availability. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving High Availability fails first?
- **S5.** A canary changes the behavior of High Availability; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does High Availability constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when High Availability meets concurrency or partial failure?
- **L3.** What breaks first around High Availability at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using High Availability?
- **L5.** How would you benchmark or validate High Availability without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can High Availability introduce?
- **L7.** How would you change a poor decision around High Availability with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for High Availability?
- **L10.** How would you turn an incident involving High Availability into a durable prevention mechanism?

## 10. Short Answers

**B1.** High Availability là phương pháp đo hoặc kiểm soát latency, capacity và failure để giữ user journey trong SLO. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của High Availability.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo SLI, error budget, saturation, p99 latency, MTTR và cost per request; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng High Availability như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh High Availability khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của High Availability**, không chỉ “dùng để làm gì”.
- Định lượng bằng SLI, error budget, saturation, p99 latency, MTTR và cost per request và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

Hãy xem **High Availability** như một boundary biến input/state thành output. Muốn hiểu sâu phải chỉ ra ai sở hữu state, lifecycle, điểm contention và behavior khi dependency chậm hoặc mất.

## 14. Internals Deep Dive

Latency là tổng service time + queueing. Dùng SLI/baseline, trace critical path và saturation để phân biệt symptom với bottleneck; thay đổi một biến và so before/after.

Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
flowchart LR
            Client --> API --> Pool --> DB
            API -.span.-> Trace["High Availability telemetry"]
            Pool -.metric.-> Trace
            DB -.span + metric.-> Trace
            Trace --> Alert["SLO / burn-rate alert"]
```

Đọc diagram từ input tới state transition và output. Tại mỗi mũi tên, hỏi: operation có block không, có retry không, state có durable không, identity nào dùng để dedupe và metric nào chứng minh bước đó khỏe.

## 16. Failure Scenario

Average che tail; retry che dependency suy yếu đến khi budget cạn. Alert theo user SLI/burn rate, saturation và queue age, rồi dùng trace tìm critical-path change.

Phân tích theo chuỗi: **trigger → saturation/incorrect state → propagation → user impact → immediate mitigation → durable prevention**. Tránh gọi retry hoặc scale là giải pháp nếu chưa chỉ ra dependency budget.

## 17. How I would debug this in production

1. Xác nhận SLI/baseline và recent change.
2. Phân rã queue time/service time theo trace.
3. Kiểm RED/USE và saturation.
4. Profile bottleneck đã khoanh vùng.
5. Canary một thay đổi và so tail/cost.

## 18. Common Misconceptions

**Sai:** average latency tốt nghĩa system khỏe. **Đúng:** tail, saturation, error semantics và user journey mới phản ánh SLO.

## 19. When NOT to use

Không optimize từ intuition hoặc microbenchmark không đại diện; đo user SLI và bottleneck trước.

## 20. What interviewer may ask next

1. **What guarantee does High Availability provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **High Availability** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [Observability](observability.md)
- [SLI/SLO/SLA](sli-slo-sla.md)
- [Incident Debugging](incident-debugging.md)
