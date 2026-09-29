# Celery Cheatsheet

- Producer → broker → worker → result/backend (optional). Queue thường at-least-once.
- Ack late + worker crash = redelivery. Ack early = có nguy cơ mất task.
- Task idempotent: business key/unique constraint/inbox; lock đơn thuần không đủ.
- Retry transient only; exponential backoff + jitter + max attempts/deadline. Poison task → DLQ/quarantine.
- Đo queue depth **và oldest age**, runtime, retry/failure, worker saturation.
- Route CPU/I/O/long task riêng; prefetch và visibility timeout phải hợp runtime.
