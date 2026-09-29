# Học trước: nối kiến thức theo quan hệ phụ thuộc

Các nhóm dưới là bản đồ chọn bài. Đọc từ ví dụ nhỏ tới cơ chế rồi mới chuyển sang production; nếu chưa hiểu một thuật ngữ, quay lại lời giải thích trong bài thay vì chỉ ghi nó vào checklist. Ví dụ slice ownership giúp hiểu channel payload, còn channel/select giúp hiểu cancellation và worker pool.

## Top 20 Golang topics to study first

1. [Slices: aliasing, append, retention](../01-go-core/arrays-slices.md)
2. [Maps: semantics và concurrency](../01-go-core/maps.md)
3. [Interfaces và typed nil](../01-go-core/interfaces.md)
4. [Error chains: Is/As/Join](../01-go-core/errors.md)
5. [Defer, cleanup và panic boundary](../01-go-core/defer.md)
6. [Memory model / happens-before](../02-memory-runtime/memory-model.md)
7. [Stack versus heap](../02-memory-runtime/stack-vs-heap.md)
8. [Escape analysis](../02-memory-runtime/escape-analysis.md)
9. [GC, GOGC, GOMEMLIMIT](../02-memory-runtime/garbage-collector.md)
10. [Goroutine lifecycle](../03-goroutines-scheduler/goroutine.md)
11. [G-M-P scheduler / syscall / netpoll](../03-goroutines-scheduler/scheduler-gmp.md)
12. [Channel internals](../04-concurrency/channels.md)
13. [Select và cancellation race](../04-concurrency/select.md)
14. [Mutex / RWMutex / atomic invariants](../04-concurrency/mutex.md)
15. [Context tree và deadlines](../05-context/context-basics.md)
16. [Worker pools và backpressure](../04-concurrency/worker-pool.md)
17. [Goroutine leaks / race detector](../04-concurrency/goroutine-leak.md)
18. [HTTP client / Transport / pooling](../06-http-backend/http-client.md)
19. [database/sql pool / transactions](../08-database/database-sql-pool.md)
20. [pprof và execution trace](../16-performance/pprof.md)

## Top 10 production topics

1. [API high latency](../20-production-scenarios/api-high-latency.md): queue versus execution time.
2. [High CPU](../20-production-scenarios/high-cpu.md): hot code, GC assists, throttling.
3. [Memory growth](../20-production-scenarios/memory-growth.md): retention versus churn/RSS.
4. [20k goroutines](../20-production-scenarios/goroutine-leak.md): stack groups và lifecycle.
5. [DB pool exhaustion](../20-production-scenarios/connection-pool-exhausted.md): holders và waiters.
6. [Slow database](../20-production-scenarios/database-slow.md): locks/plans/IO.
7. [Redis down](../20-production-scenarios/redis-down.md): bounded fallback.
8. [Kafka lag](../20-production-scenarios/kafka-lag.md): ordering và recovery capacity.
9. [Duplicate messages](../20-production-scenarios/duplicate-message.md): durable idempotency.
10. [Graceful shutdown/deployment](../06-http-backend/graceful-shutdown.md): drain, join, replay.

## Top 10 system design topics

1. [Capacity và framework](../13-system-design/system-design-framework.md)
2. [High-throughput API20k RPS](../13-system-design/design-high-throughput-api.md)
3. [Payment system](../13-system-design/design-payment-system.md)
4. [Migration 4–5B records](../13-system-design/design-migration-platform.md)
5. [Job processing](../13-system-design/design-job-processing-system.md)
6. [Notification system](../13-system-design/design-notification-system.md)
7. [Chat system](../13-system-design/design-chat-system.md)
8. [File processing](../13-system-design/design-file-processing.md)
9. [API gateway](../13-system-design/design-api-gateway.md)
10. [URL shortener](../13-system-design/design-url-shortener.md)

## Recommended learning order

Core values/ownership → memory model/GC → goroutines/scheduler → concurrency/context → HTTP/DB/pools/shutdown → Redis/Kafka/idempotency → distributed systems → architecture/platform/security → profiling/observability/testing → system design → incident drills → coding/behavioral → scored mock → cheatsheets.

Profile/test ngay trong từng module, không đợi cuối mới chạy code. Khi role tập trung data engineering, đưa migration/CDC lên ngay sau Kafka và database; Platform role ưu tiên runtime, resource limits, observability và failure isolation.

[30-day plan](30-day-plan.md) · [14-day plan](14-day-crash-plan.md) · [Dashboard](../README.md)
