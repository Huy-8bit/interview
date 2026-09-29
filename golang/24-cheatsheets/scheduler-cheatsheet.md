# Go Scheduler Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| G | Goroutine: stack và execution state. |
| M | OS thread; số M có thể lớn hơn số P. |
| P | Runtime resource để execute Go code; không là pinned physical core. |
| GOMAXPROCS | Số P; không cap G/threads. Container-aware default tùy version/config. |
| Queues | Local runnable queues giảm contention; global queue chia work; work stealing tìm runnable G. |
| Syscall | M có thể block, P release/retake; return cần reacquire P hoặc enqueue G. |
| Network | Nonblocking FD + netpoll park G, readiness wake G; disk/cgo không mặc nhiên giống. |
| Preemption | Giúp progress, không hard real-time guarantee. Implementation details đổi theo version. |

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../03-goroutines-scheduler/scheduler-gmp.md) · [Review ngày cuối](last-day-review.md)
