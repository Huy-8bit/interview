# Goroutines Scheduler

Theo dấu G/M/P qua CPU, syscall và network waits.

## Reading map

| Bài | Ưu tiên |
|---|---|
| [GOMAXPROCS và container CPU](gomaxprocs.md) | P1 |
| [Goroutine lifecycle](goroutine-lifecycle.md) | P1 |
| [Goroutine: lifetime, stack và ownership](goroutine.md) | P0 |
| [Netpoller và network readiness](netpoller.md) | P1 |
| [OS thread versus goroutine](os-thread-vs-goroutine.md) | P1 |
| [Preemption và safe points](preemption.md) | P1 |
| [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md) | P0 |
| [Scheduler interview scenarios](scheduler-scenarios.md) | P1 |
| [Blocking syscalls](syscalls.md) | P1 |
| [Work stealing và locality](work-stealing.md) | P1 |

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
