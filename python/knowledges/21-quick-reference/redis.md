# Redis Cheatsheet

- Cache-aside: miss → DB → set TTL. Dùng TTL jitter + single-flight + stale-if-error.
- Hit ratio cao chưa đủ: xem command p99, evictions, memory fragmentation, hot key, replica lag.
- TTL không phải invalidation correctness; version key/event invalidation khi cần.
- Lock: unique owner token + atomic compare-delete; lease có thể hết hạn. Invariant mạnh dùng fencing/DB constraint.
- Pub/Sub không durable; Streams có persistence/consumer group nhưng vẫn thiết kế duplicate.
- Redis down: circuit break, bounded fallback, rate-limit DB, cache warming có kiểm soát.
