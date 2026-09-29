# Distributed Systems

Module này được học theo **Why → How → Internals → Flow → Failure → Trade-off → Production**. Không đọc alphabet; đi theo dependency dưới đây và tự vẽ lại diagram trước khi xem.

## Learning order

[Fundamentals](fundamentals.md) → [Idempotency](idempotency.md) → [Retry](retry.md) → [Timeout](timeout.md) → [Circuit Breaker](circuit-breaker.md) → [Outbox Pattern](outbox-pattern.md)

## Must know

- [Fundamentals](fundamentals.md)
- [Idempotency](idempotency.md)
- [Retry](retry.md)
- [Timeout](timeout.md)
- [Circuit Breaker](circuit-breaker.md)
- [Outbox Pattern](outbox-pattern.md)

## Nice to know / second pass

- [Cap Theorem](cap-theorem.md)
- [Consistency Models](consistency-models.md)
- [Distributed Lock](distributed-lock.md)
- [Saga](saga.md)
- [Message Queue](message-queue.md)
- [Eventual Consistency](eventual-consistency.md)
- [Failure Scenarios](failure-scenarios.md)

## Recommended exercises

1. Giải thích mỗi Must-know topic trong 2 phút, không nhìn note; interviewer hỏi “why?” ít nhất ba lần.
2. Vẽ request/data/failure flow từ trí nhớ và đánh dấu source of truth, queue, timeout, retry, metric.
3. Chọn một production incident liên quan **Distributed Systems**, trình bày mitigation trước root cause và long-term prevention.
4. Load/fault test một assumption: bottleneck, duplicate, stale state hoặc dependency outage.

## All topics

- [Fundamentals](fundamentals.md)
- [Cap Theorem](cap-theorem.md)
- [Consistency Models](consistency-models.md)
- [Distributed Lock](distributed-lock.md)
- [Idempotency](idempotency.md)
- [Retry](retry.md)
- [Timeout](timeout.md)
- [Circuit Breaker](circuit-breaker.md)
- [Saga](saga.md)
- [Outbox Pattern](outbox-pattern.md)
- [Message Queue](message-queue.md)
- [Eventual Consistency](eventual-consistency.md)
- [Failure Scenarios](failure-scenarios.md)

[← Main Dashboard](../README.md)
