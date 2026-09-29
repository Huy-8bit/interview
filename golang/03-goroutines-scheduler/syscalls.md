# Blocking syscalls

## Bài toán và ví dụ đầu tiên

Read từ một file hoặc call vào thư viện native có thể giữ OS thread chờ. Nếu runtime để P gắn với thread đó mãi, công việc Go khác có thể mất cơ hội chạy dù CPU còn rảnh. Cơ chế syscall của scheduler quản lý việc tách quyền thực thi khỏi thread đang chờ khi phù hợp.

## Đi từng bước qua một tình huống

G trên M1 đi vào blocking syscall. P có thể được nhả hoặc runtime lấy lại để M2 chạy G khác. Khi syscall trở về, M1 cần P để tiếp tục Go code; không có P sẵn thì G có thể được enqueue. Vì vậy số M tăng không đồng nghĩa Go bỏ qua giới hạn GOMAXPROCS.

## Hiểu cơ chế từ kết quả quan sát

Network descriptor được netpoller hỗ trợ thường có đường chờ khác với một blocking syscall giữ thread. Cgo có thêm constraints và chi phí chuyển biên. Không phải mỗi syscall đều tạo M mới ngay; runtime có thể reuse idle thread và chọn đường theo tính chất lời gọi.

## Khái niệm và mô hình làm việc

Syscall chạy kernel code trên M; Go runtime có protocol để Go work khác vẫn có P.

## Cơ chế và những ranh giới cần giữ

P có thể release/retake; syscall return thử lấy lại P hoặc enqueue G. Short syscall không luôn dẫn đến M mới.

## Áp dụng vào hệ thống thật

File reads và C libraries cần capacity riêng nếu block OS threads.

## Những đường lỗi cần hiểu

Disk stall kéo dài làm tăng blocked M và queued work.

## Lần theo bằng chứng khi có sự cố

Correlate thread stacks, disk latency, cgo call counts và trace syscall regions.

## Đánh đổi và giới hạn sử dụng

Goroutine wrapper không biến syscall thành cancelable; giới hạn concurrency ở boundary.

## Thực hành, debugging và kết luận

Nếu thread count tăng sau đổi thư viện DB/DNS/native, so stack và cấu hình cgo trước/sau. Đo số call đang in-flight và duration, đặt concurrency bound hoặc dùng API có cancellation thật. Context không cưỡng bức dừng một native call phớt lờ nó.


## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
