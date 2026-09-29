# Top 50 Senior Backend Questions

Câu hỏi English, answer cues Vietnamese. Tự trả lời60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## API and security

### 1. How should an idempotency key be scoped?

<details>
<summary>Answer</summary>

Theo tenant+operation, kèm request hash và retention phủ replay horizon.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 2. How should reused keys with different payloads behave?

<details>
<summary>Answer</summary>

Reject conflict để không trộn hai logical operations.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 3. How do authentication and authorization differ?

<details>
<summary>Answer</summary>

Identity khác quyền action/resource; kiểm tenant ở data access.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 4. Why use keyset pagination for deep pages?

<details>
<summary>Answer</summary>

Stable indexed order tránh offset scan lớn; cần unique tiebreaker.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 5. How do you rate-limit without unlimited label cardinality?

<details>
<summary>Answer</summary>

Bucket theo identity policy, metric theo bounded tier/route, log sampling cho tenant.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 6. How can SSRF bypass a simple hostname denylist?

<details>
<summary>Answer</summary>

Redirect/DNS resolution/private address changes cần connect-time policy.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 7. What should JWT validation check beyond signature?

<details>
<summary>Answer</summary>

Algorithm policy, issuer, audience, expiry/not-before và trusted keys.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 8. What is the difference between OAuth2 and OIDC?

<details>
<summary>Answer</summary>

Delegated authorization versus identity layer; token purposes khác nhau.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 9. How do you roll out an additive API change safely?

<details>
<summary>Answer</summary>

Test old/new clients, optional fields và unknown enums theo compatibility contract.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>

### 10. When should an API reject overload instead of queueing?

<details>
<summary>Answer</summary>

Khi queued work không còn deadline/memory/downstream budget.

Đọc sâu: [API idempotency key](../07-api-design/idempotency.md).

</details>


## Data and transactions

### 11. How do you prevent concurrent double reservation?

<details>
<summary>Answer</summary>

Conditional atomic update/constraint hoặc transaction isolation phù hợp invariant.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 12. Why can Repeatable Read allow write skew?

<details>
<summary>Answer</summary>

Stable snapshots không tự serialize cross-row predicate invariants.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 13. What should a serialization retry repeat?

<details>
<summary>Answer</summary>

Whole transaction với bounded retry/deadline, không chỉ last statement.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 14. How would you remove N+1 without exploding result rows?

<details>
<summary>Answer</summary>

Batch queries hoặc join có pagination/entity aggregation đúng.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 15. What causes idle-in-transaction incidents?

<details>
<summary>Answer</summary>

Application giữ Tx ngoài useful work, locks/snapshot/pool slot không release.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 16. Why are replicas not a universal read scaling fix?

<details>
<summary>Answer</summary>

Lag, read-your-writes và primary-dependent reads vẫn cần authority.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 17. How do indexes trade reads for writes?

<details>
<summary>Answer</summary>

Lookup nhanh hơn nhưng update/storage/WAL cost tăng.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 18. How would you perform expand-contract migration?

<details>
<summary>Answer</summary>

Add compatible schema, deploy both-compatible code, migrate, verify rồi remove old shape.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 19. Why is a check-then-insert application guard insufficient?

<details>
<summary>Answer</summary>

Concurrent replicas cùng thấy absent; unique constraint/atomic operation cần thiết.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>

### 20. What bounds total database connections during rollout?

<details>
<summary>Answer</summary>

Max replicas+surge nhân per-pod pools, cộng worker/admin reserve.

Đọc sâu: [Transactions và short critical sections](../08-database/transactions.md).

</details>


## Messaging and consistency

### 21. How does an outbox avoid lost events?

<details>
<summary>Answer</summary>

Domain state và event intent commit cùng DB transaction; relay recover từ durable intent.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 22. Why can outbox relays publish duplicates?

<details>
<summary>Answer</summary>

Crash sau broker ack trước mark progress tạo replay window.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 23. How do you handle a poisoned message?

<details>
<summary>Answer</summary>

Classify permanent error, quarantine/DLQ với owner/replay plan và ordering policy.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 24. What does Kafka ordering actually cover?

<details>
<summary>Answer</summary>

Records trong partition; application completion order còn do workers quyết định.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 25. How do you preserve contiguous offset progress?

<details>
<summary>Answer</summary>

Track completed prefix, không advance qua unfinished record.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 26. What distinguishes broker ack from business completion?

<details>
<summary>Answer</summary>

Broker accepted record khác consumer durable side effect.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 27. How does retry-topic routing affect order?

<details>
<summary>Answer</summary>

Failed record có thể bị later records vượt; cần per-key sequencing/version guard.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 28. What must eventual consistency guarantee operationally?

<details>
<summary>Answer</summary>

Delivery/retry/merge tiến triển và reconciliation xử lý gaps/DLQ.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 29. Why can a leader require fencing?

<details>
<summary>Answer</summary>

Old process có thể ghi sau lease expiry; target phải reject stale epoch.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>

### 30. How would you compare saga and local transactions?

<details>
<summary>Answer</summary>

Saga phối hợp multiple local commits với compensation, local Tx đơn giản nếu cùng authority.

Đọc sâu: [Distributed systems: safety, liveness và replay](../12-distributed-systems/fundamentals.md).

</details>


## Scale and reliability

### 31. How do you estimate backlog drain time?

<details>
<summary>Answer</summary>

Backlog/(processing−arrival) trong steady rates; μ phải lớn hơn λ.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 32. What makes cache invalidation race-prone?

<details>
<summary>Answer</summary>

Concurrent stale read có thể refill sau write/invalidate.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 33. How would you survive a hot-key stampede?

<details>
<summary>Answer</summary>

Coalesce, jitter/early refresh, bounded stale và source admission.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 34. Why can a circuit breaker flap?

<details>
<summary>Answer</summary>

Threshold/window quá nhạy, half-open probes đồng loạt và recovery chưa ổn.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 35. How do bulkheads change capacity efficiency?

<details>
<summary>Answer</summary>

Isolation giữ reserve giảm blast radius nhưng unused capacity khó share.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 36. What does CPU-based HPA miss?

<details>
<summary>Answer</summary>

DB/pool/I/O waits với CPU thấp vẫn làm latency saturation.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 37. How would you verify a 20k RPS claim?

<details>
<summary>Answer</summary>

Realistic payload/data/auth, independent offered load, timeout accounting, failures và P99 gates.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 38. How do you choose a shard key?

<details>
<summary>Answer</summary>

Access locality, cardinality/skew, transaction boundaries và rebalance cost.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 39. Why can a 1KiB compressed input use much more memory?

<details>
<summary>Answer</summary>

Decompression/decoded objects/duplicates/buffers tăng working set.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>

### 40. What is a meaningful error budget policy?

<details>
<summary>Answer</summary>

Eligible user events, measurable good fraction và burn-rate dẫn release/mitigation decisions.

Đọc sâu: [Design High-Throughput API — 20,000 RPS](../13-system-design/design-high-throughput-api.md).

</details>


## Operations and judgment

### 41. What is your first action in a multi-service outage?

<details>
<summary>Answer</summary>

Assess user impact/scope và assign coordination, rồi reversible mitigation theo evidence.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 42. When should you roll back versus investigate longer?

<details>
<summary>Answer</summary>

Impact, recent-change correlation, rollback safety và data/schema compatibility.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 43. How do you prove graceful shutdown worked?

<details>
<summary>Answer</summary>

In-flight/worker join, accepted work reconciliation và resources closed đúng order.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 44. Why should liveness avoid depending on a shared DB?

<details>
<summary>Answer</summary>

Restarting callers không chữa DB và có thể gây cascade.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 45. How would you protect observability from becoming an outage source?

<details>
<summary>Answer</summary>

Bounded exporter queues/cardinality, sampling, deadlines và dropped-data metrics.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 46. How do you migrate billions of rows with ongoing writes?

<details>
<summary>Answer</summary>

Coordinated snapshot+CDC boundary, idempotent versioned apply, checkpoints và verification.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 47. What must be checked before migration cutover?

<details>
<summary>Answer</summary>

Lag boundary reached, counts/hash/key gaps resolved, DLQ handled và rollback ownership.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 48. How do you defend an architectural trade-off?

<details>
<summary>Answer</summary>

Requirements, alternatives, measured assumptions, failure behavior và revisit trigger.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 49. How do you mentor concurrency reasoning?

<details>
<summary>Answer</summary>

Ask ownership/blocking/exit/join, rồi test cancellation và explain invariant.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>

### 50. What should a blameless postmortem produce?

<details>
<summary>Answer</summary>

Evidence timeline, contributing systems, action owners và measurable prevention.

Đọc sâu: [Incident debugging với evidence](../17-observability/incident-debugging.md).

</details>
