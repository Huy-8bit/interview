# Đồng bộ dữ liệu và vòng đời công việc

Bắt đầu counter bị mất cập nhật và producer/consumer chờ nhau. Mutex bảo vệ invariant dữ liệu, channel phối hợp trao đổi, còn context và join quản lý lúc kết thúc. Sau các primitive mới ghép worker pool/pipeline; mọi ví dụ đều cần xác định ai gửi, ai đóng và điều gì xảy ra khi caller bỏ cuộc.

## Bắt đầu và cách thực hành

Bắt đầu với [mutex](mutex.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

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

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
