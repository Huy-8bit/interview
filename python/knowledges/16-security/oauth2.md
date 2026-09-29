# OAuth 2.0

> **Phạm vi phỏng vấn:** Security · **Ưu tiên:** P1/P2 · **Mindset:** Why → How → Trade-off → Production.

## 1. What is it?

OAuth 2.0 là security control hoặc threat class tại trust boundary của web/API system.

## 2. Why does it matter?

Senior Engineer cần hiểu **OAuth 2.0** để security là thuộc tính end-to-end, không phải middleware thêm sau. Điểm phỏng vấn nằm ở khả năng nêu invariant, điều kiện áp dụng và failure behavior, không nằm ở việc thuộc định nghĩa.

## 3. How does it work?

Xác định asset/actor/trust boundary, enforce server-side deny-by-default, validate canonical input, minimize privilege và log audit không lộ secret/PII.

Khi reasoning, đi theo chuỗi: **input → state transition → output → failure → recovery**. Quan sát `attack surface, auth failure, secret age, patch latency và incident blast radius` và phân biệt symptom, bottleneck với root cause.

## 4. Example

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Decision:
    topic: str
    invariant: str
    metric: str

decision = Decision(
    topic='OAuth 2.0',
    invariant="Không làm mất hoặc lặp business effect",
    metric="p99 latency và error rate",
)
```

Ví dụ biến quyết định về **OAuth 2.0** thành invariant và tín hiệu vận hành có thể kiểm chứng.

## 5. Production Use Case

Multi-tenant API áp dụng OAuth 2.0 bằng policy test, secret rotation và abuse simulation; alert dựa signal thay vì log mọi payload.

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
| Tối ưu/thiết kế xoay quanh OAuth 2.0 | Kiểm soát rõ constraint chính | Tăng complexity và coupling | Metric chứng minh đây là bottleneck/risk |
| Giữ baseline đơn giản | Ít dependency, dễ debug | Có thể chạm giới hạn sớm | Traffic vừa, invariant vẫn được giữ |
| Managed service/library | Giảm vận hành hạ tầng | Cost, lock-in, giới hạn control | SLA và economics phù hợp |
| Tự vận hành/customize | Kiểm soát sâu | Ownership và failure surface lớn | Có năng lực vận hành và nhu cầu thật |

## 8. Interview Questions

### Basic / Mid-level (10)

- **B1.** What is OAuth 2.0, and which concrete problem does it address?
- **B2.** Explain the main internal mechanism behind OAuth 2.0.
- **B3.** Which guarantees does OAuth 2.0 provide, and which does it not provide?
- **B4.** Which metrics or observations reveal the behavior of OAuth 2.0?
- **B5.** What is the most common misconception about OAuth 2.0?
- **B6.** How would you test assumptions involving OAuth 2.0?
- **B7.** Which edge cases or failure modes matter most for OAuth 2.0?
- **B8.** How can OAuth 2.0 affect latency, throughput, memory, or correctness?
- **B9.** Which runtime conditions or configuration choices change the behavior of OAuth 2.0?
- **B10.** When is a different or simpler approach better than relying on OAuth 2.0?

### Production Scenarios (5)

- **S1.** A release involving OAuth 2.0 triples p99 while averages look normal. How do you investigate and mitigate?
- **S2.** A critical dependency around OAuth 2.0 is unavailable for ten minutes. Define degraded behavior and recovery.
- **S3.** Two concurrent operations expose a correctness gap related to OAuth 2.0. Which invariant and atomic boundary fix it?
- **S4.** Traffic grows from 1,000 to 20,000 RPS. Which measured limit involving OAuth 2.0 fails first?
- **S5.** A canary changes the behavior of OAuth 2.0; success rate is flat but saturation rises. Promote or roll back?

## 9. Senior-level Questions

- **L1.** How does OAuth 2.0 constrain the surrounding architecture and operational model?
- **L2.** Which subtle correctness issue appears when OAuth 2.0 meets concurrency or partial failure?
- **L3.** What breaks first around OAuth 2.0 at 20,000 RPS or 100× data volume?
- **L4.** Where should admission control or backpressure be placed when using OAuth 2.0?
- **L5.** How would you benchmark or validate OAuth 2.0 without a misleading microbenchmark?
- **L6.** Which hidden coupling or migration cost can OAuth 2.0 introduce?
- **L7.** How would you change a poor decision around OAuth 2.0 with no downtime?
- **L8.** What production evidence would make you choose a different approach?
- **L9.** How do correctness, latency, cost, and complexity trade off for OAuth 2.0?
- **L10.** How would you turn an incident involving OAuth 2.0 into a durable prevention mechanism?

## 10. Short Answers

**B1.** OAuth 2.0 là security control hoặc threat class tại trust boundary của web/API system. Trả lời tốt nối definition với constraint/invariant và một use case cụ thể.

**B2.** Mô tả state, lifecycle, boundary và failure path; không dừng ở public API của OAuth 2.0.

**B3.** Nêu lúc tạo, lúc sử dụng, lúc release/commit và điều xảy ra khi timeout hoặc cancellation.

**B4.** Đo attack surface, auth failure, secret age, patch latency và incident blast radius; luôn tách average khỏi tail và success khỏi useful result.

**B5.** Lỗi phổ biến là dùng OAuth 2.0 như mặc định mà không xác định ownership, limit và fallback.

**B6.** Test invariant trước, sau đó integration test failure path, concurrency và representative load.

**B7.** Xét timeout, duplicate, stale state, overload, dependency loss và recovery/reconciliation.

**B8.** Đo critical path, contention, queueing và amplification; throughput cao không bù được p99 xấu.

**B9.** Deadline, concurrency limit, retention/TTL, resource budget, telemetry và rollout policy phải explicit.

**B10.** Tránh OAuth 2.0 khi bài toán đơn giản hơn giải được invariant với ít state và operational cost hơn.

Cấu trúc câu trả lời: **Definition → Why → How → Trade-off → Production example**. Với câu scenario: **stabilize → observe → hypothesize → verify → mitigate → prevent**.

## 11. Follow-up Questions

- **F1.** What assumption in your answer is most risky?
- **F2.** How would you prove that with metrics or an experiment?
- **F3.** What changes if the operation is not idempotent?
- **F4.** Where would you add timeout, retry, and backpressure?
- **F5.** What is your rollback and data-reconciliation plan?

## 12. Key Takeaways

- Nói được **vai trò, constraint hoặc invariant của OAuth 2.0**, không chỉ “dùng để làm gì”.
- Định lượng bằng attack surface, auth failure, secret age, patch latency và incident blast radius và có baseline trước tối ưu.
- Thiết kế cho timeout, duplicate, overload, partial failure và recovery.
- Mọi tối ưu đều có chi phí về correctness, complexity, latency hoặc money.
- Production-ready nghĩa là có owner, alert, runbook, canary, rollback và reconciliation.


## 13. Mental Model

Hãy xem **OAuth 2.0** như một boundary biến input/state thành output. Muốn hiểu sâu phải chỉ ra ai sở hữu state, lifecycle, điểm contention và behavior khi dependency chậm hoặc mất.

## 14. Internals Deep Dive

Bắt đầu từ asset, actor và trust boundary; authentication không thay authorization. Enforce server-side, least privilege và audit, đồng thời thiết kế key/secret rotation và incident containment.

Implementation detail có thể đổi theo version; khi trả lời interview, nêu rõ CPython/PostgreSQL/Redis/framework version nếu kết luận dựa vào behavior nội bộ thay vì public contract.

## 15. Request / Data Flow

```mermaid
flowchart LR
            Actor --> Boundary["Trust boundary"]
            Boundary --> AuthN
            AuthN --> AuthZ
            AuthZ --> Topic["OAuth 2.0 control"]
            Topic --> Resource
            Topic --> Audit[(Audit log)]
```

Đọc diagram từ input tới state transition và output. Tại mỗi mũi tên, hỏi: operation có block không, có retry không, state có durable không, identity nào dùng để dedupe và metric nào chứng minh bước đó khỏe.

## 16. Failure Scenario

Credential hợp lệ vẫn có thể truy cập sai tenant nếu authorization thiếu. Fail closed cho sensitive operation, rotate/revoke credential và giữ audit không lộ secret.

Phân tích theo chuỗi: **trigger → saturation/incorrect state → propagation → user impact → immediate mitigation → durable prevention**. Tránh gọi retry hoặc scale là giải pháp nếu chưa chỉ ra dependency budget.

## 17. How I would debug this in production

1. Contain credential/session và preserve audit evidence.
2. Xác định actor/resource/tenant/action bị ảnh hưởng.
3. Kiểm authN, authZ policy và trust boundary.
4. Rotate/revoke/fix least privilege.
5. Backfill detection và regression test.

## 18. Common Misconceptions

**Sai:** JWT hợp lệ nghĩa request được phép. **Đúng:** token chỉ hỗ trợ authentication; authorization phải kiểm resource/tenant/action.

## 19. When NOT to use

Không tự thiết kế crypto/token protocol khi chuẩn và managed identity đáp ứng; custom security mở thêm attack surface.

## 20. What interviewer may ask next

1. **What guarantee does OAuth 2.0 provide, and what does it explicitly not guarantee?**
2. **Which implementation detail changes across versions or runtimes?**
3. **Where is the first queue or contention point under high load?**
4. **What happens if the dependency times out after committing state?**
5. **How would you observe, degrade, and recover this in production?**
6. **Which simpler design would you choose at 100 RPS, and when would you evolve it?**

## 21. Check Your Understanding

1. Nếu throughput tăng 20× nhưng downstream capacity không đổi, **OAuth 2.0** sẽ tạo queue/backpressure ở đâu?
2. Timeout xảy ra ngay sau một state transition; caller có thể kết luận điều gì và không thể kết luận điều gì?
3. Metric, trace span và log field tối thiểu nào giúp phân biệt application, dependency và network latency?

<details>
<summary>Answer</summary>

1. Queue xuất hiện tại bounded resource đầu tiên: worker/thread/semaphore/connection pool/broker hoặc dependency. Nếu không có bound, overload chuyển thành memory growth và timeout storm.
2. Caller chỉ biết chưa nhận response trong deadline; operation có thể chưa chạy, đang chạy hoặc đã commit. Cần operation identity/idempotency và status/reconciliation.
3. Dùng end-to-end latency + queue/service time, correlation/trace ID, dependency spans, error/retry classification và saturation của pool/queue/resource.

</details>

## 22. See also

- [API Security](api-security.md)
- [Secrets](secrets-management.md)
