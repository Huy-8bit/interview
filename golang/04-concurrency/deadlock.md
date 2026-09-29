# Deadlock và wait-for graph

## Bài toán và ví dụ đầu tiên

A giữ lock user rồi đợi lock account. B giữ lock account rồi đợi lock user. Cả hai cần người kia mở khóa trước khi có thể tiến tiếp. Đây là vòng chờ, một dạng deadlock; CPU có thể rất thấp vì các goroutine đang ngủ chờ.

## Đi từng bước qua một tình huống

Vẽ actor và tài nguyên: A giữ U, A đợi C, B giữ C, B đợi U. Áp một thứ tự lấy lock thống nhất, chẳng hạn luôn U trước C, loại bỏ vòng chờ này. Với channel, main gửi vào unbuffered channel trước khi tạo receiver cũng không thể tiến triển; không nhất thiết phải có hai mutex mới deadlock.

## Hiểu cơ chế từ kết quả quan sát

Runtime có thể phát hiện một số trường hợp toàn chương trình không còn đường tiến triển, nhưng một HTTP server còn goroutine network/timer có thể chỉ deadlock một subsystem. Không thấy lỗi fatal deadlock không chứng minh service không kẹt. Timeout của caller cũng không phá mutex.Lock hay plain channel operation đang chờ.

## Khái niệm và mô hình làm việc

Deadlock khi tasks chờ lẫn nhau hoặc chờ event không bao giờ có; production có thể chỉ deadlock một subsystem.

## Cơ chế và những ranh giới cần giữ

Vẽ G giữ resource nào, đang chờ gì; cycle lock order và channel handshake là hai nguồn phổ biến. Runtime global deadlock detection không bắt mọi partial deadlock trong server còn network work.

## Áp dụng vào hệ thống thật

Shutdown stop producer trước close queue, drain workers rồi close dependencies.

## Những đường lỗi cần hiểu

Wait trước close/unblock; unbuffered send trước launching receiver; recursive mutex.

## Lần theo bằng chứng khi có sự cố

Lấy nhiều goroutine dumps để xác nhận stacks đứng yên; tìm cycle và owner đã exit.

## Đánh đổi và giới hạn sử dụng

Timeout giảm blast radius nhưng không sửa lock protocol; giữ order đơn giản.

## Thực hành, debugging và kết luận

Lấy nhiều goroutine dump theo thời gian và tìm stack không đổi cùng chuỗi tài nguyên chờ. Khi shutdown, tránh Wait worker trước khi signal khiến worker có thể thoát. Sửa thứ tự sở hữu và giải phóng; thêm Sleep chỉ thay xác suất va chạm. Giảm số lock giữ đồng thời thường dễ bảo trì hơn cơ chế retry lấy lock phức tạp.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
