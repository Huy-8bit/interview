# Exactly Once Myth

> **Phạm vi phỏng vấn:** Celery · **Ưu tiên:** P0/P1 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

End-to-end exactly-once effect hiếm khi đến từ queue; broker acknowledgement race tạo redelivery, còn external side effect nằm ngoài broker transaction.

## 2. Why does it matter?

Senior Engineer cần hiểu **Exactly Once Myth** để tách long-running work khỏi request path nhưng vẫn kiểm soát duplicate và retry. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Thiết kế at-least-once delivery cùng idempotent consumer, unique constraint/inbox và reconciliation. Exactly-once scope cụ thể có thể đạt bằng transactional boundary hẹp.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `queue depth, task age, runtime, retry rate, failure rate và worker saturation` và phân biệt symptom, bottleneck với root cause.

## 4. Example

```sql
CREATE TABLE processed_request (
    tenant_id bigint NOT NULL,
    idempotency_key text NOT NULL,
    request_hash text NOT NULL,
    response jsonb,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (tenant_id, idempotency_key)
);
```

`INSERT ... ON CONFLICT` phải nằm cùng transaction với business write; cùng key nhưng khác `request_hash` bị từ chối.

## 5. Production Use Case

Worker gửi email rồi crash trước ack sẽ chạy lại; ghi delivery record trước/sau provider call với provider idempotency key để duplicate không gửi lần hai.

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
| Tối ưu/thiết kế xoay quanh Exactly Once Myth | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is Exactly Once Myth, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind Exactly Once Myth.
- **B3.** Which guarantees does Exactly Once Myth provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of Exactly Once Myth?
- **B5.** What is the most common misconception about Exactly Once Myth?
- **B6.** How would you test assumptions involving Exactly Once Myth?
- **B7.** Which edge cases or failure modes matter most for Exactly Once Myth?
- **B8.** How can Exactly Once Myth affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of Exactly Once Myth?
- **B10.** When is a different or simpler approach better than relying on Exactly Once Myth?

### Production Scenarios (5)

- **S1.** A release involving Exactly Once Myth triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around Exactly Once Myth is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to Exactly Once Myth. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving Exactly Once Myth fails first?
- **S5.** A canary changes the behavior of Exactly Once Myth; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does Exactly Once Myth constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when Exactly Once Myth meets concurrency or partial failure?
- **L3.** What breaks first around Exactly Once Myth at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using Exactly Once Myth?
- **L5.** How would you benchmark or validate Exactly Once Myth without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can Exactly Once Myth introduce?
- **L7.** How would you change a poor decision around Exactly Once Myth with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for Exactly Once Myth?
- **L10.** How would you turn an incident involving Exactly Once Myth into a durable prevention mechanism?

## 10. Short Answers

**B1.** End-to-end exactly-once effect hiếm khi đến từ queue; broker acknowledgement race tạo redelivery, còn external side effect nằm ngoài broker transaction. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của Exactly Once Myth.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo queue depth, task age, runtime, retry rate, failure rate và worker saturation; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng Exactly Once Myth như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh Exactly Once Myth khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của Exactly Once Myth**, không chỉ “dùng để làm gì”.
- Định lượng bằng queue depth, task age, runtime, retry rate, failure rate và worker saturation và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

Exactly-once phải hỏi: một lần ở đâu—broker delivery, database transition hay external effect? Mỗi boundary có failure window khác nhau.

## 14. Internals Deep Dive

Tách producer publish, broker delivery, worker reservation/execution/ACK và business state. Mỗi boundary có crash window; đo oldest age và business completion, không chỉ queue length.

Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
sequenceDiagram
    participant B as Broker
    participant W as Worker
    participant DB
    B->>W: deliver task
    W->>DB: commit business effect
    DB-->>W: committed
    Note over W: worker crashes before ACK
    B->>W: redelivery after lease / reconnect
    W->>DB: same effect attempted again
    DB-->>W: unique key returns prior result
```

Đọc diagram từ input tới state transition và output. Tại mỗi mũi tên, hỏi: operation có block không, có retry không, state có durable không, identity nào dùng để dedupe và metric nào chứng minh bước đó khỏe.

## 16. Failure Scenario

Worker có thể commit rồi crash trước ACK, hoặc ACK sớm rồi crash trước effect. Thiết kế idempotent business transition, retry budget, DLQ và reconciliation thay vì dựa task ID/lock.

Phân tích theo chuỗi: **trigger → saturation/incorrect state → propagation → user impact → immediate mitigation → durable prevention**. Tránh gọi retry hoặc scale là giải pháp nếu chưa chỉ ra dependency budget.

## 17. How I would debug this in production

1. Đo oldest task age, runtime percentile, retry/failure.
2. So active/reserved/prefetch và worker RSS/CPU.
3. Trace publish → delivery → attempt → business state → ACK.
4. Kiểm visibility/consumer timeout và deploy termination.
5. Quarantine poison task; reconcile duplicate/missing effect.

## 18. Common Misconceptions

**Sai:** task thành công trong log nghĩa business effect exactly once. **Đúng:** ACK, result backend và domain commit là các boundary độc lập.

## 19. When NOT to use

Không đưa work cần response tức thì hoặc transaction atomic đơn giản qua queue; queue thêm lag, duplicate và operational surface.

## 20. What interviewer may ask next

1. **What guarantee does Exactly Once Myth provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **Exactly Once Myth** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [Task Lifecycle](task-lifecycle.md)
- [Idempotency](idempotency.md)
- [Duplicate Task Incident](../20-senior-scenarios/celery-task-duplicate.md)
