# Go Scheduler Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Một goroutine chờ network chưa có dữ liệu là waiting; khi socket ready nó trở thành runnable, rồi phải được chọn mới running. Work stealing chỉ giúp phân runnable work, không làm dữ liệu mạng tới nhanh hoặc mở một mutex đang bị giữ. P cấp tài nguyên chạy Go code cho M, còn OS lập lịch M trên CPU. Vì vậy thread count, goroutine count và GOMAXPROCS là ba con số khác nhau.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

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


[Đọc sâu](../03-goroutines-scheduler/scheduler-gmp.md) · [Review ngày cuối](last-day-review.md)
