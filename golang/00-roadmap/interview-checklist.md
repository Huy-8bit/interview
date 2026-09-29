# Interview readiness checklist

Đánh dấu theo khả năng thực tế, không chỉ đã đọc file.

- [ ] [Goroutine](../03-goroutines-scheduler/goroutine.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Go Scheduler / G-M-P](../03-goroutines-scheduler/scheduler-gmp.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Channels](../04-concurrency/channels.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Select](../04-concurrency/select.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Mutex](../04-concurrency/mutex.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Context](../05-context/context-basics.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Memory model](../02-memory-runtime/memory-model.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Stack vs Heap](../02-memory-runtime/stack-vs-heap.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Escape Analysis](../02-memory-runtime/escape-analysis.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Garbage Collector](../02-memory-runtime/garbage-collector.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Slices](../01-go-core/arrays-slices.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Maps](../01-go-core/maps.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Interfaces](../01-go-core/interfaces.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [nil](../01-go-core/nil.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [net/http](../06-http-backend/net-http.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [HTTP client](../06-http-backend/http-client.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [HTTP connection pooling](../06-http-backend/connection-pooling.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [database/sql](../08-database/database-sql.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Database connection pool](../08-database/database-sql-pool.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Error handling](../01-go-core/errors.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Graceful shutdown](../06-http-backend/graceful-shutdown.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Race condition](../04-concurrency/race-condition.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Goroutine leak](../04-concurrency/goroutine-leak.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Worker pool](../04-concurrency/worker-pool.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [pprof](../16-performance/pprof.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [Distributed systems](../12-distributed-systems/fundamentals.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.
- [ ] [System Design](../13-system-design/system-design-framework.md): giải thích mechanism, vẽ flow, nêu failure, chọn debugging evidence.

## Practical gates

- [ ] Chạy default tests và race detector; hiểu negative race demo cố ý fail.
- [ ] Đọc CPU/heap/goroutine profile và phân biệt waiting với runnable.
- [ ] Thiết kế worker pool có bound, error policy, cancellation và join.
- [ ] Size DB/HTTP pools theo max replicas+surge và downstream capacity.
- [ ] Chứng minh idempotency qua crash sau commit trước ack.
- [ ] Vẽ5 diagrams cho một system design và tính units rõ ràng.
- [ ] Kể2 STAR stories thật với contribution, alternative và lesson.
- [ ] Full mock đạt mục tiêu cá nhân và không còn critical correctness gaps.

[30 ngày](30-day-plan.md) · [14 ngày](14-day-crash-plan.md) · [Mock](../23-mock-interview/full-mock-interview.md)
