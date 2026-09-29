# System Design Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Start | Requirements, invariant, workload distribution và SLO trước chọn technology. |
| Arithmetic | RPS × mean seconds = mean in-flight; bytes×rate×retention rồi replicas/index overhead. |
| Contract | API status/idempotency, data owner, durable commit point, unknown outcome. |
| Go | Bound workers/queues/pools, ctx budgets, shared clients và graceful drain. |
| Failure | Response lost after commit, cache down, lag, stale owner, schema skew, overload. |
| Evidence | User SLIs + queue age + profiles/traces + durable reconciliation. |
| Scale | Find bottleneck, capacity knee, max replicas/surge budgets; shard khi justified. |
| Evolution | State assumptions, next measured trigger, safe migration và rollback data plan. |

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../13-system-design/README.md) · [Review ngày cuối](last-day-review.md)
