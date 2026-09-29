# Từ goroutine tới cách runtime chia CPU

Học goroutine bằng một hàm chạy đồng thời có điểm chờ hoàn tất, rồi đọc G–M–P để hiểu nhiều công việc chia sẻ ít thread/core. Runnable là sẵn sàng nhưng đợi lượt, waiting là chưa thể tiến triển; phân biệt đó là nền tảng của trace và debugging latency. Các bài work stealing, netpoller, syscall và preemption mở từng đường đi cụ thể.

## Bắt đầu và cách thực hành

Bắt đầu với [goroutine](goroutine.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

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

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
