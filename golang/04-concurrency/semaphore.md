# Semaphore và admission

## Bài toán và ví dụ đầu tiên

Dịch vụ có thể nhận nhiều HTTP request nhưng chỉ muốn tối đa 20 call tới một partner. Semaphore là bộ đếm quyền sử dụng tài nguyên; có slot thì bắt đầu, hết slot thì chờ có giới hạn hoặc từ chối.

## Đi từng bước qua một tình huống

Với buffered channel capacity 20, gửi một token trước call biểu diễn acquire, receive token sau call biểu diễn release. Acquire phải select cùng ctx.Done vì request có thể hết hạn khi còn chờ. Chỉ release sau acquire thành công; defer release đặt đúng sau điểm đó giúp đường lỗi trả slot.

## Hiểu cơ chế từ kết quả quan sát

Nếu tạo một goroutine cho mỗi job rồi mới acquire, số call được giới hạn nhưng số goroutine chờ vẫn có thể tăng vô hạn. Acquire trước launch khi owner có thể chờ; với server có nhiều handler sẵn, thêm admission bound để hạn chế tổng hàng chờ. Semaphore không tự tạo queue bền hoặc fairness theo tenant.

## Khái niệm và mô hình làm việc

Semaphore bound số operations in-flight; acquire phải trước tạo work tiêu tốn tài nguyên.

## Cơ chế và những ranh giới cần giữ

Buffered channel tokens hoặc weighted semaphore; acquire dùng select ctx. Release đúng một lần sau successful acquire.

## Áp dụng vào hệ thống thật

Giới hạn outbound calls độc lập từng dependency để tránh một host làm cạn mọi workers.

## Những đường lỗi cần hiểu

Spawn goroutine trước acquire tạo vô hạn waiting G; release token chưa acquire làm deadlock/panic tùy implementation.

## Lần theo bằng chứng khi có sự cố

Đo active permits, acquire wait và rejected requests; test cancel trước/sau acquire.

## Đánh đổi và giới hạn sử dụng

Bound concurrency không bound rate hoặc payload bytes; thêm queue và rate limits khi cần.

## Thực hành, debugging và kết luận

Đo active permits, wait duration và rejected rate. Nếu luôn đủ 20 slot nhưng throughput giảm, partner chậm đang giữ slot lâu; nâng lên 200 có thể làm partner quá tải hơn. Tách semaphore theo dependency để một host chậm không giữ mọi slot của dịch vụ; với job trọng lượng khác nhau cân nhắc weighted permits và kiểm tra starvation.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
