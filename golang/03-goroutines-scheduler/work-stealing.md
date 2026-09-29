# Work stealing và locality

## Bài toán và ví dụ đầu tiên

Một batch tạo 1000 job trên P1 trong khi P2 gần như rảnh. Nếu mỗi P chỉ làm local queue của mình, CPU có thể nhàn dù còn nhiều việc. Work stealing cho P thiếu việc tìm runnable goroutine từ nơi khác để cân bằng tải.

## Đi từng bước qua một tình huống

Giả sử P1 có 100 job CPU ngắn, P2 không có job. Scheduler có thể chuyển một nhóm runnable work sang P2, rồi hai phía xử lý song song trong giới hạn CPU. Job đang chờ network chưa runnable nên lấy nó sang P2 không làm nó tiến triển; scheduler cần job thật sự có thể chạy.

## Hiểu cơ chế từ kết quả quan sát

Locality nghĩa là dữ liệu và công việc có xu hướng gần nơi vừa sử dụng, giúp cache và giảm tranh chấp queue chung. Stealing đổi một phần locality lấy cân bằng. Batch size, chọn victim và queue policy là implementation detail theo Go version; ứng dụng không được dựa vào thứ tự job lấy từ các P.

## Khái niệm và mô hình làm việc

P thiếu work tìm runnable G từ P khác để dùng CPU còn rảnh.

## Cơ chế và những ranh giới cần giữ

Local queues giảm global contention; stealing lấy batch để giảm synchronization cost. Exact victim selection và batch size phụ thuộc release.

## Áp dụng vào hệ thống thật

Fan-out CPU batch được chia giữa P, nhưng task cực dài vẫn làm tail latency cao.

## Những đường lỗi cần hiểu

Một task giữ lock toàn cục khiến nhiều P rảnh; stealing không tạo parallelism qua serialized critical section.

## Lần theo bằng chứng khi có sự cố

Trace runnable delay, CPU utilization và mutex profile; xem task size skew.

## Đánh đổi và giới hạn sử dụng

Chia task nhỏ giúp cân bằng nhưng quá nhỏ tăng schedule overhead; không tự tune runtime queues.

## Thực hành, debugging và kết luận

Trace giúp phân biệt một P thiếu work với toàn hệ thống đang chờ lock. Chia job quá lớn gây skew giữa worker; quá nhỏ tăng scheduling overhead. Nếu global mutex serialize mọi job, work stealing không tạo parallelism qua critical section; giảm lock hold hoặc partition state mới tác động đúng bottleneck.



## Một diễn tiến tải lệch để phân biệt ba nguyên nhân

Giả sử P1 có 100 job, mỗi job xử lý 1 ms CPU, P2 không có local work và cả hai đều được quyền dùng CPU. Nếu các job thực sự độc lập và runnable, việc chuyển một nhóm sang P2 giảm thời gian P2 nhàn. Tổng work vẫn là 100 ms CPU theo giả định; thời gian tường có thể giảm khi chạy song song, nhưng không thể suy chính xác giảm một nửa vì còn scheduling, cache và OS policy.

Bây giờ đổi 100 job thành 100 goroutine chờ cùng một socket chưa có dữ liệu. P2 rảnh là hợp lý vì chưa có work runnable. Stealing không làm network response tới sớm hơn. Nếu profile chỉ cho thấy waiting, câu hỏi cần chuyển sang deadline/dependency, không phải queue balancing.

Đổi lần nữa:100 jobs đều cần giữ cùng mutex cho toàn phép tính 1 ms. Các goroutine chờ mutex chưa thể cùng tiến triển trong critical section; hai P vẫn không tạo 100 ms CPU work thành 50 ms wall time bằng stealing. Sửa cần tách state theo key hoặc giảm phạm vi độc quyền nếu invariant cho phép. Bỏ lock để benchmark nhanh hơn làm thay đổi correctness.

Khi đọc trace, đối chiếu trạng thái runnable/waiting và critical sections thay vì chỉ thấy một P ít hoạt động. Một benchmark tạo jobs từ cùng một goroutine có thể cho runtime phân tải khác source topology production. Ghi job sizes, skew, CPU quota và Go version khi so kết quả; không dựa vào thứ tự victim hoặc số job lấy mỗi lần như API ổn định.

## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
