# Goroutine lifecycle

## Bài toán và ví dụ đầu tiên

Một hàm khởi chạy worker rồi return mà không lưu cách dừng hoặc chờ. Worker vẫn có thể hợp lệ lúc đầu, nhưng khi shutdown không ai biết nó đang dùng tài nguyên nào. Lifecycle là toàn bộ đường từ tạo tới kết thúc, không chỉ dòng go.

## Đi từng bước qua một tình huống

Worker bắt đầu ở runnable, được scheduler chạy, có thể waiting ở input rồi lại runnable khi có event. Khi function return, defer chạy theo quy tắc và worker kết thúc. Caller có kết quả chưa chắc worker đã cleanup; cần tín hiệu finish ở đúng cuối phạm vi nếu caller sẽ đóng dependency.

## Hiểu cơ chế từ kết quả quan sát

Owner phải định nghĩa nguồn việc, ai close input, điều kiện lỗi, cancellation và join. Cancel là yêu cầu, không là xác nhận; Wait chỉ chờ, không tạo điều kiện thoát. Một worker dài hạn nên nhận service context và có stop protocol riêng với request context.

## Khái niệm và mô hình làm việc

Mỗi task đi qua runnable, running, waiting rồi dead; waiting không đồng nghĩa leak.

## Cơ chế và những ranh giới cần giữ

Cancel là tín hiệu; join xác nhận task đã dừng. Parent cần wait ngay cả khi child được báo cancel.

## Áp dụng vào hệ thống thật

Consumer service bắt đầu workers, ngừng fetch, cancel work theo policy rồi Wait trước đóng DB.

## Những đường lỗi cần hiểu

Đóng channel khi producer còn gửi gây panic; Wait trước khi unblock producer gây deadlock.

## Lần theo bằng chứng khi có sự cố

Vẽ dependency graph của shutdown và thu stack tại deadline; thử cancel giữa từng stage.

## Đánh đổi và giới hạn sử dụng

Drain giữ work nhưng kéo dài shutdown; abort cần replay/idempotency.

## Thực hành, debugging và kết luận

Test worker đang idle, đang xử lý và đang gửi result khi shutdown. Điều phối bằng channel rồi đợi finished với timeout bảo vệ test. Dùng profile sau drain để tìm worker còn giữ stack ngoài lifetime hữu ích, thay vì chỉ đếm mọi goroutine của process.


## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
