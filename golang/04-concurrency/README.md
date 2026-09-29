# Concurrency

Thiết kế synchronization và lifecycle có proof.

## Reading map

| Bài | Ưu tiên |
|---|---|
| [Atomics và immutable publication](atomic.md) | P1 |
| [Buffered versus unbuffered](buffered-vs-unbuffered.md) | P1 |
| [Channel internals và synchronization](channels.md) | P0 |
| [Chọn concurrency pattern](concurrency-patterns.md) | P1 |
| [Condition variable và predicate](condition-variable.md) | P1 |
| [Deadlock và wait-for graph](deadlock.md) | P1 |
| [Fan-in và fan-out](fan-in-fan-out.md) | P1 |
| [Goroutine leaks: blocked work còn giữ tài nguyên](goroutine-leak.md) | P0 |
| [Livelock và retry synchronization](livelock.md) | P1 |
| [Mutex: invariants, contention và lock ownership](mutex.md) | P0 |
| [sync.Once và initialization](once.md) | P1 |
| [Pipeline: ownership ở từng stage](pipeline.md) | P1 |
| [Race condition versus data race](race-condition.md) | P0 |
| [RWMutex và writer latency](rwmutex.md) | P1 |
| [Select: readiness, cancellation và fairness](select.md) | P0 |
| [Semaphore và admission](semaphore.md) | P1 |
| [sync.Map versus typed map](sync-map.md) | P1 |
| [WaitGroup: join và lifecycle](waitgroup.md) | P1 |
| [Worker pool và bounded concurrency](worker-pool.md) | P0 |

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
