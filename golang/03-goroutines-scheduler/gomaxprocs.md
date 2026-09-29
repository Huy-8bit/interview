# GOMAXPROCS và container CPU

## Bài toán và ví dụ đầu tiên

Máy có nhiều core nhưng container chỉ được dùng một phần CPU. GOMAXPROCS liên quan số P có thể thực thi Go code đồng thời; nó không phải số goroutine tối đa và cũng không bảo đảm OS cấp đủ CPU cho các thread.

## Đi từng bước qua một tình huống

Với GOMAXPROCS=2, hàng nghìn goroutine vẫn có thể tồn tại, nhưng chỉ một số thread tương ứng P thực thi Go code đồng thời. Nhiều goroutine waiting không cần thêm P. Nếu work CPU-bound, tăng P có thể giúp cho tới khi bị giới hạn core/quota hoặc contention.

## Hiểu cơ chế từ kết quả quan sát

Thread count có thể lớn hơn P count vì syscall, cgo và các trạng thái thread khác. Default GOMAXPROCS và việc xét cgroup có thay đổi qua phiên bản Go; ghi giá trị runtime thực tế thay vì đoán từ số core host. Throttling là việc OS tạm ngừng cấp CPU khi dùng hết quota theo chính sách container.

## Khái niệm và mô hình làm việc

GOMAXPROCS điều khiển số P, không giới hạn G hoặc tổng OS threads.

## Cơ chế và những ranh giới cần giữ

Default Linux từ Go 1.25 có container awareness và cập nhật tùy config/module version; explicit environment/runtime settings có thể override. Đọc runtime value đang chạy.

## Áp dụng vào hệ thống thật

CPU quota 2 cores cần benchmark concurrency hợp quota; limits, requests và affinity là khái niệm khác nhau.

## Những đường lỗi cần hiểu

P quá nhiều làm burst dùng hết quota sớm rồi throttle, P99 cao dù CPU average trông vừa đủ.

## Lần theo bằng chứng khi có sự cố

So runtime.GOMAXPROCS(0), cgroup quota, throttled periods và scheduler latency; canary một thay đổi.

## Đánh đổi và giới hạn sử dụng

Nhiều P có lợi khi CPU thực sự có sẵn, nhưng tăng lock/cache contention; không đặt bằng request concurrency.

## Thực hành, debugging và kết luận

Đo throughput, P99, runnable delay và throttling dưới cùng offered load khi thử một giá trị mới. Tăng P khi CPU quota nhỏ có thể làm burst dùng quota sớm rồi phải chờ, tăng latency đuôi. Nếu bottleneck ở DB pool, điều chỉnh P thường không giải quyết gốc.


## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
