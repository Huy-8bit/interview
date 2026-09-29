# Celery

Module này được học theo **Why → How → Internals → Flow → Failure → Trade-off → Production**. Không đọc alphabet; đi theo dependency dưới đây và tự vẽ lại diagram trước khi xem.

## Learning order

[Architecture](architecture.md) → [Task Lifecycle](task-lifecycle.md) → [Retry](retry.md) → [Idempotency](idempotency.md) → [Exactly Once Myth](exactly-once-myth.md) → [Production Problems](production-problems.md)

## Must know

- [Architecture](architecture.md)
- [Task Lifecycle](task-lifecycle.md)
- [Retry](retry.md)
- [Idempotency](idempotency.md)
- [Exactly Once Myth](exactly-once-myth.md)
- [Production Problems](production-problems.md)

## Nice to know / second pass

- [Broker Worker](broker-worker.md)
- [Celery Redis](celery-redis.md)
- [Task Routing](task-routing.md)
- [Scheduled Task](scheduled-task.md)

## Recommended exercises

1. Giải thích mỗi Must-know topic trong 2 phút, không nhìn note; interviewer hỏi “why?” ít nhất ba lần.
2. Vẽ request/data/failure flow từ trí nhớ và đánh dấu source of truth, queue, timeout, retry, metric.
3. Chọn một production incident liên quan **Celery**, trình bày mitigation trước root cause và long-term prevention.
4. Load/fault test một assumption: bottleneck, duplicate, stale state hoặc dependency outage.

## All topics

- [Architecture](architecture.md)
- [Broker Worker](broker-worker.md)
- [Task Lifecycle](task-lifecycle.md)
- [Retry](retry.md)
- [Idempotency](idempotency.md)
- [Exactly Once Myth](exactly-once-myth.md)
- [Celery Redis](celery-redis.md)
- [Task Routing](task-routing.md)
- [Scheduled Task](scheduled-task.md)
- [Production Problems](production-problems.md)

[← Main Dashboard](../README.md)
