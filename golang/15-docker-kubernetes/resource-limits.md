# Resource requests, limits và Go budgets

## Bài toán và ví dụ đầu tiên

Container bị CPU throttled dù host còn CPU rảnh vì nó đã dùng hết quota. Memory OOM có thể xảy ra dù live heap thấp hơn limit vì RSS còn có stacks/runtime/cgo và phần khác. Resource limits phải được đo ở cả Go và OS.

## Đi từng bước qua một tình huống

CPU request ảnh hưởng scheduling theo nền tảng; CPU limit áp policy runtime của container. Memory limit là biên OOM của môi trường, khác GOMEMLIMIT soft target của Go. Đặt headroom cho các phần ngoài heap và burst thay vì dùng hai con số bằng nhau.

## Hiểu cơ chế từ kết quả quan sát

GOMAXPROCS và GC behavior phụ thuộc Go version/config; inspect effective values. Tăng parallelism có thể làm quota hết sớm và latency đuôi cao. Giảm heap target quá thấp khi live set lớn làm GC tốn CPU mà không thu được đủ.

## Khái niệm và mô hình làm việc

CPU request phục vụ scheduling/share; CPU limit có thể throttle; memory limit có thể kill.

## Cơ chế và những ranh giới cần giữ

Choose memory headroom từ live heap+stacks+runtime+native+buffers; GOMEMLIMIT soft và không bao toàn RSS. GOMAXPROCS effective cần kiểm tra runtime config.

## Áp dụng vào hệ thống thật

Set requests dựa steady state và burst measurement; reserve memory cho spike và profile overhead.

## Những đường lỗi cần hiểu

GC thrash sát memory limit; CPU bursts bị throttle làm timeout/retry; low requests khiến poor placement.

## Lần theo bằng chứng khi có sự cố

RSS/heap, OOMKilled, throttled periods, scheduler latency và GC assists.

## Đánh đổi và giới hạn sử dụng

Không đặt limit bằng live heap sample duy nhất; workload distribution và native memory matters.

## Thực hành, debugging và kết luận

Load test cùng limits production, xem throttled time, RSS/live heap, GC CPU và P99. Right-size từ dữ liệu peak/steady state và failure burst. Đừng dùng memory limit lớn hơn để che cache không bound; sửa ownership và queue budget.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
