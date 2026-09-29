# Mutex profile

## Bài toán và ví dụ đầu tiên

Nhiều handlers cùng đợi một cache lock làm latency tăng dù từng lookup rất nhanh. Mutex profile giúp tìm contention — thời gian các goroutine mất vì tranh khóa — theo cách runtime quy chiếu samples.

## Đi từng bước qua một tình huống

Nếu holder giữ lock trong HTTP call, profile có thể chỉ về đường Unlock/holder stack tương ứng, nên phải đọc critical section bao quanh thay vì chỉ dòng Lock ở waiter. Một lock thường xuyên nhưng giữ rất ngắn khác một lock ít lần nhưng giữ vài giây.

## Hiểu cơ chế từ kết quả quan sát

Sampling/aggregation không phải đồng hồ chính xác cho từng goroutine và không tự nói invariant nào cần giữ. Chia lock theo key có thể giảm contention nhưng thêm lock ordering cho operation nhiều key. RWMutex cũng có reader/writer trade-off, không mặc định nhanh hơn.

## Khái niệm và mô hình làm việc

Mutex profile đo contention cost theo sampled lock-holder release paths, không chỉ nơi waiter gọi Lock.

## Cơ chế và những ranh giới cần giữ

Enable runtime.SetMutexProfileFraction với budget; inspect cumulative wait contribution và critical section callers.

## Áp dụng vào hệ thống thật

Cache LRU global lock giữ trong serialization tạo tail latency.

## Những đường lỗi cần hiểu

Hiểu aggregate waiter time như wall duration một request; profile disabled nên empty bị hiểu là không contention.

## Lần theo bằng chứng khi có sự cố

So mutex với block profile/trace và hold-time instrumentation có bounded cardinality.

## Đánh đổi và giới hạn sử dụng

Sampling giảm overhead nhưng có noise; không bật tối đa vô thời hạn.

## Thực hành, debugging và kết luận

Đo hold duration, waiter latency và workload skew. Copy state cần thiết dưới lock rồi làm I/O ngoài lock nếu có version check phù hợp khi ghi lại. Benchmark và race test sau thay đổi để không đổi giảm contention thành đọc state không nhất quán.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)

## Thực hành có điều kiện kiểm chứng

Capture test/load có contention thực bằng `go test -mutexprofile=mutex.out`, rồi inspect `top -cum` và `list` vùng critical section. Empty profile từ test không tranh lock không chứng minh production không contention. Đặt giả thuyết “serialization dưới lock” rồi move copy/snapshot ngoài lock nếu invariant cho phép; compare writer P99 và race results.
