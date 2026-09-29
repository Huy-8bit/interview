# Distributed Systems

Reason về safety/liveness/unknown outcomes và recovery.

## Reading map

| Bài | Ưu tiên |
|---|---|
| [Bulkheads và capacity isolation](bulkhead.md) | P1 |
| [CAP: quyết định trong network partition](cap-theorem.md) | P1 |
| [Circuit breaker state machine](circuit-breaker.md) | P1 |
| [Consistency models và client observations](consistency.md) | P1 |
| [Leases, locks và fencing tokens](distributed-lock.md) | P1 |
| [Eventual consistency như product contract](eventual-consistency.md) | P1 |
| [Distributed failure matrix](failure-scenarios.md) | P1 |
| [Distributed systems: safety, liveness và replay](fundamentals.md) | P0 |
| [Distributed idempotency và ambiguous outcomes](idempotency.md) | P1 |
| [Leader election và epochs](leader-election.md) | P1 |
| [Transactional outbox](outbox-pattern.md) | P1 |
| [Retries như một capacity policy](retry.md) | P1 |
| [Saga và compensating actions](saga.md) | P1 |
| [Timeout và failure detection](timeout.md) | P1 |

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
