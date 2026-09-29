# Suy luận khi chỉ một phần hệ thống thất bại

Tình huống trung tâm là remote commit nhưng response mất. Từ đó học timeout, retry, idempotency và outbox, rồi consistency, saga và authority/lease. Mỗi kỹ thuật giải quyết một failure boundary; ghép đúng cần biết invariant nào nằm trong một transaction và state nào phải được đối soát.

## Bắt đầu và cách thực hành

Bắt đầu với [fundamentals](fundamentals.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

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

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
