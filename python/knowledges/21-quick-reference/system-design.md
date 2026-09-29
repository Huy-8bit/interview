# System Design Cheatsheet

1. Clarify user, core flow, out-of-scope, consistency, SLO, retention/compliance.
2. Estimate peak RPS, concurrency (`RPS × latency`), bandwidth, storage/day × retention.
3. API + data model + invariant/source of truth.
4. Draw simple read/write flow; deep-dive largest bottleneck.
5. Cache/queue/shard only khi access pattern/number yêu cầu.
6. Failure: deadline, bounded retry+jitter, idempotency, backpressure, DLQ, reconciliation.
7. Security, observability, cost, migration, rollback.

Senior sentence: “My assumption is X; if metric Y crosses Z, I would move from A to B.”
