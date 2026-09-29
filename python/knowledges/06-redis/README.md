# Redis

Module này được học theo **Why → How → Internals → Flow → Failure → Trade-off → Production**. Không đọc alphabet; đi theo dependency dưới đây và tự vẽ lại diagram trước khi xem.

## Learning order

[Redis Internals](redis-internals.md) → [Caching](caching.md) → [Cache Patterns](cache-patterns.md) → [Persistence](persistence.md) → [Sentinel Cluster](sentinel-cluster.md) → [Failure Scenarios](failure-scenarios.md)

## Must know

- [Redis Internals](redis-internals.md)
- [Caching](caching.md)
- [Cache Patterns](cache-patterns.md)
- [Persistence](persistence.md)
- [Sentinel Cluster](sentinel-cluster.md)
- [Failure Scenarios](failure-scenarios.md)

## Nice to know / second pass

- [TTL](ttl.md)
- [Distributed Lock](distributed-lock.md)
- [Rate Limiting](rate-limiting.md)
- [Pub Sub](pub-sub.md)
- [Streams](streams.md)

## Recommended exercises

1. Giải thích mỗi Must-know topic trong 2 phút, không nhìn note; interviewer hỏi “why?” ít nhất ba lần.
2. Vẽ request/data/failure flow từ trí nhớ và đánh dấu source of truth, queue, timeout, retry, metric.
3. Chọn một production incident liên quan **Redis**, trình bày mitigation trước root cause và long-term prevention.
4. Load/fault test một assumption: bottleneck, duplicate, stale state hoặc dependency outage.

## All topics

- [Redis Internals](redis-internals.md)
- [Caching](caching.md)
- [Cache Patterns](cache-patterns.md)
- [TTL](ttl.md)
- [Distributed Lock](distributed-lock.md)
- [Rate Limiting](rate-limiting.md)
- [Pub Sub](pub-sub.md)
- [Streams](streams.md)
- [Persistence](persistence.md)
- [Sentinel Cluster](sentinel-cluster.md)
- [Failure Scenarios](failure-scenarios.md)

[← Main Dashboard](../README.md)
