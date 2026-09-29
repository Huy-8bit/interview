# Concurrency Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Ownership | Mỗi go: ai tạo, ai cancel, block ở đâu, ai join? |
| Channel | Nil send/receive block; closed send panic; closed receive drain rồi zero,false. |
| Select | Multiple ready chọn pseudo-random; không ưu tiên cancel; default trong loop có thể spin. |
| Mutex | Protect whole invariant; no copy after use, no reentrant; tránh I/O dưới lock. |
| RWMutex | Không upgrade/recursive lock; benchmark với Mutex, readers nhiều chưa đủ lý do. |
| Atomic | Counter/small transitions; nhiều atomic fields không tạo transaction. |
| WaitGroup | Add trước go, Done guaranteed, Wait là join; không truyền error. |
| Pool | Bound workers, queue count/bytes và downstream; overload có reject/drop/durable policy. |

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../04-concurrency/README.md) · [Review ngày cuối](last-day-review.md)
