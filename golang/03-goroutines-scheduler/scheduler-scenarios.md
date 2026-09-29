## Khái niệm và mô hình làm việc

## Bài toán và ví dụ đầu tiên

Hai incident cùng P99 cao có thể cần hai cách sửa ngược nhau: một service CPU bão hòa, service kia CPU thấp nhưng mọi goroutine chờ DB. Scheduler scenario bắt đầu từ trạng thái công việc và tài nguyên thực, không bắt đầu bằng tăng GOMAXPROCS.

## Đi từng bước qua một tình huống

Case A có CPU 95%, runnable queue tăng và profile chỉ vào JSON parse; giảm công việc CPU hoặc thêm capacity là hướng hợp lý. Case B CPU 20%, stack ở DB acquire và pool InUse=max; thêm P không tạo connection. Case C thread count cao sau dùng cgo; cần xem native calls có block hay không.

## Hiểu cơ chế từ kết quả quan sát

Waiting G chưa thể chạy vì điều kiện chưa đạt; runnable G cần CPU nhưng chưa được chọn. Trace phân biệt hai loại thời gian này, còn CPU profile chỉ lấy mẫu lúc thực thi CPU. Một khoảng trắng trong CPU profile không nói rõ đang chờ mạng, lock hay quota; cần đối chiếu timeline và hệ thống.

Đọc workload qua runnable/waiting/syscall trước khi đề xuất tune runtime.

## Cơ chế và những ranh giới cần giữ

CPU-bound: queue runnable; I/O-bound: waiting; mutex contention: wait tập trung; cgo: M tăng. Mỗi trường hợp cần bằng chứng khác nhau.

## Áp dụng vào hệ thống thật

So ba lần chạy: busy compute, HTTP chậm, lock giữ lâu; thu CPU/goroutine/trace cho mỗi lần.

## Những đường lỗi cần hiểu

Tăng workers chữa I/O throughput nhưng làm DB queue vượt deadline; profile trên laptop không phản ánh CPU quota.

## Lần theo bằng chứng khi có sự cố

Đối chiếu P99, queue depth, CPU throttling, goroutine states và load generator schedule.

## Đánh đổi và giới hạn sử dụng

Không chỉ nhìn utilization trung bình; tail latency cần xem burst và contention.

## Thực hành, debugging và kết luận

Chọn một giả thuyết, một metric phân biệt và một thay đổi nhỏ để kiểm chứng. Canary concurrency limit, so completion rate và P99 cùng offered load. Đừng tăng workers, pool và P cùng lúc vì sẽ không biết thay đổi nào giúp và có thể chuyển overload sang dependency khác.


## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
