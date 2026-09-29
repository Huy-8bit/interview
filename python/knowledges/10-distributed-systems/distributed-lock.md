# Distributed Lock

> **Phạm vi phỏng vấn:** Distributed Systems · **Ưu tiên:** P0/P1 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

Distributed lock phối hợp nhiều process qua shared service nhưng lease expiry và network pause khiến mutual exclusion tuyệt đối khó đảm bảo.

## 2. Why does it matter?

Senior Engineer cần hiểu **Distributed Lock** để network không đáng tin và retry có thể đổi correctness của business operation. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Owner token ngăn client khác unlock; lease cần bounded work/renewal. Fencing token tăng đơn điệu giúp downstream từ chối stale holder; DB constraint thường an toàn hơn cho invariant dữ liệu.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `availability, stale-read window, duplicate rate, convergence time và p99 latency` và phân biệt symptom, bottleneck với root cause.

## 4. Example

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Decision:
    topic: str
    invariant: str
    metric: str

decision = Decision(
    topic='Distributed Lock',
    invariant="Không làm mất hoặc lặp business effect",
    metric="p99 latency và error rate",
)
```

Ví dụ biến quyết định về **Distributed Lock** thành invariant và tín hiệu vận hành có thể kiểm chứng.

## 5. Production Use Case

Hai worker xử lý cùng vehicle không chỉ dựa Redis lock: dùng fencing token hoặc conditional DB update để worker đã mất lease không ghi đè kết quả mới.

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
| Tối ưu/thiết kế xoay quanh Distributed Lock | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is Distributed Lock, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind Distributed Lock.
- **B3.** Which guarantees does Distributed Lock provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of Distributed Lock?
- **B5.** What is the most common misconception about Distributed Lock?
- **B6.** How would you test assumptions involving Distributed Lock?
- **B7.** Which edge cases or failure modes matter most for Distributed Lock?
- **B8.** How can Distributed Lock affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of Distributed Lock?
- **B10.** When is a different or simpler approach better than relying on Distributed Lock?

### Production Scenarios (5)

- **S1.** A worker pauses beyond lease expiry, resumes, and overwrites a newer result. Show how fencing prevents it.
- **S2.** Redis lock service becomes partitioned. Which safety/liveness guarantee can you actually claim?
- **S3.** Two lock acquisitions appear successful during failover. Can a database constraint protect the invariant better?
- **S4.** Lock renewal traffic overloads the coordinator. Redesign granularity and critical-section duration.
- **S5.** A process crashes while holding a lock. Explain lease, owner token, cleanup, and reconciliation.

## 9. Senior-level Questions

- **L1.** How does Distributed Lock constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when Distributed Lock meets concurrency or partial failure?
- **L3.** What breaks first around Distributed Lock at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using Distributed Lock?
- **L5.** How would you benchmark or validate Distributed Lock without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can Distributed Lock introduce?
- **L7.** How would you change a poor decision around Distributed Lock with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for Distributed Lock?
- **L10.** How would you turn an incident involving Distributed Lock into a durable prevention mechanism?

## 10. Short Answers

**B1.** Distributed lock phối hợp nhiều process qua shared service nhưng lease expiry và network pause khiến mutual exclusion tuyệt đối khó đảm bảo. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của Distributed Lock.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo availability, stale-read window, duplicate rate, convergence time và p99 latency; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng Distributed Lock như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh Distributed Lock khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của Distributed Lock**, không chỉ “dùng để làm gì”.
- Định lượng bằng availability, stale-read window, duplicate rate, convergence time và p99 latency và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

Hãy xem **Distributed Lock** như một boundary biến input/state thành output. Muốn hiểu sâu phải chỉ ra ai sở hữu state, lifecycle, điểm contention và behavior khi dependency chậm hoặc mất.

## 14. Internals Deep Dive

Assume message có thể delay/drop/duplicate/reorder và node có thể pause/restart. Đặt identity, deadline, atomic boundary, durable state và reconciliation trước khi chọn middleware.

Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
flowchart LR
            Caller -->|request / message| A["Service A"]
            A --> Topic["Distributed Lock boundary"]
            Topic -->|network may delay / duplicate / fail| B["Service B"]
            B --> Durable[(Durable state)]
            Durable --> Reconcile["Retry / reconcile"]
```

Đọc diagram từ input tới state transition và output. Tại mỗi mũi tên, hỏi: operation có block không, có retry không, state có durable không, identity nào dùng để dedupe và metric nào chứng minh bước đó khỏe.

## 16. Failure Scenario

Network partition/timeout biến outcome thành unknown. Không suy diễn failure từ timeout; dùng operation identity, durable state, retry có budget, circuit/bulkhead và reconciliation.

Phân tích theo chuỗi: **trigger → saturation/incorrect state → propagation → user impact → immediate mitigation → durable prevention**. Tránh gọi retry hoặc scale là giải pháp nếu chưa chỉ ra dependency budget.

## 17. How I would debug this in production

1. Vẽ timeline theo correlation/message/operation ID.
2. Phân biệt timeout, rejection, duplicate và stale observation.
3. Xác định last durable state ở từng component.
4. Kiểm retry/deadline/circuit/queue lag.
5. Reconcile source of truth với projection/external effect.

## 18. Common Misconceptions

**Sai:** timeout chứng minh operation thất bại. **Đúng:** server có thể đã commit; timeout chỉ nói caller chưa quan sát response.

## 19. When NOT to use

Không dùng consensus/lock/saga nếu một local transaction hoặc unique constraint giải được invariant.

## 20. What interviewer may ask next

1. **What guarantee does Distributed Lock provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **Distributed Lock** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [Idempotency](idempotency.md)
- [Retry](retry.md)
- [Timeout](timeout.md)
- [Outbox](outbox-pattern.md)
