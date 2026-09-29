# Pipeline: ownership ở từng stage

## Bài toán và ví dụ đầu tiên

Xử lý file gồm đọc, decode, transform và ghi. Pipeline tách các stage để bước đọc file tiếp theo có thể chồng lấp với transform file hiện tại. Mỗi channel giữa hai stage là nơi chuyển dữ liệu và cũng là nơi có thể tích tụ hàng chờ.

## Đi từng bước qua một tình huống

Decode tạo output rồi transform nhận. Nếu writer cuối cùng lỗi và bỏ đọc, transform có thể kẹt send, rồi decode cũng kẹt send theo. Owner phải cancel toàn pipeline và mọi send/receive cần quan sát tín hiệu đó. Chỉ thêm ctx vào receive không đủ nếu goroutine đang mắc ở send output.

## Hiểu cơ chế từ kết quả quan sát

Mỗi output có một owner close sau khi mọi sender của stage dừng. Payload chuyển qua nhiều stage cần quy định có được mutate tại chỗ không; buffer pooling đặc biệt nguy hiểm nếu stage trước trả buffer về pool khi stage sau vẫn đọc. Khi muốn reuse, tín hiệu ownership quay lại phải đi sau lần sử dụng cuối.

## Khái niệm và mô hình làm việc

Pipeline nối các stage bằng channels; mỗi output có owner close và mỗi blocking point có cancellation.

## Cơ chế và những ranh giới cần giữ

Stage đọc đến input closed hoặc ctx done; send output cũng select ctx. Coordinator cancel rồi join toàn pipeline khi downstream dừng.

## Áp dụng vào hệ thống thật

File processing decode-transform-write với stage concurrency theo CPU và target DB capacity.

## Những đường lỗi cần hiểu

Stage cuối bỏ đọc khiến mọi upstream kẹt send; chỉ cancel receive nhưng send không cancelable.

## Lần theo bằng chứng khi có sự cố

Goroutine profile group theo stage, queue age per edge và check close owner.

## Đánh đổi và giới hạn sử dụng

Buffer giúp burst cục bộ nhưng tăng retained payloads; pipeline chỉ đáng khi stage overlap có lợi.

## Thực hành, debugging và kết luận

Đo queue age và throughput từng stage để biết chỗ nghẽn. Decode CPU-bound không nên dùng cùng worker count với writer DB-bound một cách máy móc. Pipeline tăng khả năng chồng lấp nhưng cũng thêm lifecycle và error propagation; với workload nhỏ, một hàm tuần tự có deadline thường dễ debug và đủ nhanh.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
