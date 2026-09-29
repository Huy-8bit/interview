# OS thread versus goroutine

## Bài toán và ví dụ đầu tiên

OS thread do hệ điều hành lập lịch; goroutine do Go runtime tổ chức lên các thread đó. Mục tiêu là cho nhiều công việc chờ I/O dùng code tuần tự mà không buộc giữ một thread cho mỗi công việc.

## Đi từng bước qua một tình huống

Một goroutine chờ unbuffered channel có thể park để thread chạy goroutine khác. Một blocking native call có thể giữ thread. Vì vậy câu “goroutine nhẹ” cần gắn với loại công việc và dữ liệu nó giữ, không chỉ so kích thước stack khởi đầu.

## Hiểu cơ chế từ kết quả quan sát

Stack goroutine có thể tăng và runtime quản lý trạng thái lời gọi; OS vẫn quyết định thread nào được chạy trên CPU. GOMAXPROCS quản lý parallel Go execution thông qua P, không giới hạn tổng goroutine hay thread. LockOSThread chỉ dùng khi API đòi thread affinity, chẳng hạn một số native library.

## Khái niệm và mô hình làm việc

OS schedule threads; Go runtime multiplex G trên M với P. Concurrency là nhiều việc đang tiến triển, parallelism là thực thi cùng lúc.

## Cơ chế và những ranh giới cần giữ

OS thread có kernel resources; G có growable stack và runtime state. Blocking cgo có thể giữ M lâu nên thread count vẫn tăng.

## Áp dụng vào hệ thống thật

I/O-heavy gateway có hàng nghìn socket nhưng số thread chạy Go gần capacity CPU.

## Những đường lỗi cần hiểu

Một library gọi blocking C mỗi request làm hết thread/FD dù GOMAXPROCS thấp.

## Lần theo bằng chứng khi có sự cố

Xem OS thread count, cgo stacks và execution trace; không suy từ NumGoroutine sang số thread.

## Đánh đổi và giới hạn sử dụng

G phù hợp Go-managed work; thread affinity chỉ dùng khi API native yêu cầu.

## Thực hành, debugging và kết luận

Đo cả goroutine count, thread count, CPU và live memory. 100000 idle connections có thể hợp lệ nhưng payload và buffer của mỗi connection vẫn cần budget. Chọn goroutine cho công việc độc lập, giới hạn admission và tránh pin thread khi không có yêu cầu thực.


## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
