# Production Scenario

Module này được học theo **Why → How → Internals → Flow → Failure → Trade-off → Production**. Không đọc alphabet; đi theo dependency dưới đây và tự vẽ lại diagram trước khi xem.

## Learning order

[Production Outage Response](production-down.md) → [API Latency Regression](api-slow.md) → [PostgreSQL High CPU Incident](database-high-cpu.md) → [PostgreSQL Deadlock Incident](database-deadlock.md) → [Redis Outage](redis-down.md)

## Must know

- [Production Outage Response](production-down.md)
- [API Latency Regression](api-slow.md)
- [PostgreSQL High CPU Incident](database-high-cpu.md)
- [PostgreSQL Deadlock Incident](database-deadlock.md)
- [Redis Outage](redis-down.md)

## Nice to know / second pass

- [Duplicate Message Handling](duplicate-message.md)
- [Duplicate Celery Task](celery-task-duplicate.md)
- [Python Memory Leak Incident](memory-leak.md)
- [Scaling FastAPI from 1,000 to 20,000 RPS](high-traffic.md)
- [Data Consistency Incident](data-consistency.md)
- [Legacy System Refactoring](legacy-system-refactoring.md)

## Recommended exercises

1. Giải thích mỗi Must-know topic trong 2 phút, không nhìn note; interviewer hỏi “why?” ít nhất ba lần.
2. Vẽ request/data/failure flow từ trí nhớ và đánh dấu source of truth, queue, timeout, retry, metric.
3. Chọn một production incident liên quan **Production Scenario**, trình bày mitigation trước root cause và long-term prevention.
4. Load/fault test một assumption: bottleneck, duplicate, stale state hoặc dependency outage.

## All topics

- [Production Outage Response](production-down.md)
- [API Latency Regression](api-slow.md)
- [PostgreSQL High CPU Incident](database-high-cpu.md)
- [PostgreSQL Deadlock Incident](database-deadlock.md)
- [Redis Outage](redis-down.md)
- [Duplicate Message Handling](duplicate-message.md)
- [Duplicate Celery Task](celery-task-duplicate.md)
- [Python Memory Leak Incident](memory-leak.md)
- [Scaling FastAPI from 1,000 to 20,000 RPS](high-traffic.md)
- [Data Consistency Incident](data-consistency.md)
- [Legacy System Refactoring](legacy-system-refactoring.md)

[← Main Dashboard](../README.md)
