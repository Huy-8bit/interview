# Container resources và process model

## Bài toán và ví dụ đầu tiên

Binary chạy tốt trên laptop nhưng trong container bị OOM hoặc CPU throttling. Container chia namespace và áp resource policy của OS; nó không là một máy riêng với tài nguyên vô hạn hoặc môi trường giống host.

## Đi từng bước qua một tình huống

Application thấy filesystem/process/network theo cấu hình container, còn cgroup limits có thể giới hạn CPU/memory. RSS gồm nhiều phần ngoài live heap; GOMEMLIMIT không là hard cap container. Signal tới process chính cần được xử lý để drain công việc trước termination.

## Hiểu cơ chế từ kết quả quan sát

Image là artifact filesystem/config dùng để tạo container; container là instance đang chạy. Không lưu dữ liệu cần bền chỉ ở writable layer nếu lifecycle có thể thay thế. User permissions, CA certificates và timezone data có thể ảnh hưởng Go binary dù code compile thành một file.

## Khái niệm và mô hình làm việc

Namespaces isolate views; cgroups budget CPU/memory/process resources; host kernel vẫn shared.

## Cơ chế và những ranh giới cần giữ

CPU quota có thể throttle; memory limit có thể OOM kill; PID limits ảnh hưởng threads. Requests khác limits trong Kubernetes.

## Áp dụng vào hệ thống thật

Tune Go concurrency/soft memory limit với headroom cho native memory và runtime.

## Những đường lỗi cần hiểu

Host CPU nhiều nhưng pod quota thấp; RSS chạm limit dù heap nhỏ; too many OS threads.

## Lần theo bằng chứng khi có sự cố

cgroup metrics, throttled periods, OOM events, process RSS và Go runtime metrics.

## Đánh đổi và giới hạn sử dụng

Isolation không thay application limits; container memory phải gồm tất cả retained buffers.

## Thực hành, debugging và kết luận

Test image với limits và user giống deployment, kiểm tra DNS/TLS và shutdown. Đo throttling/OOM events bên cạnh Go profiles. Chọn image nhỏ để giảm phần mềm phải vận hành nhưng vẫn giữ các runtime assets ứng dụng thực sự cần.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
