# Chọn concurrency pattern

## Bài toán và ví dụ đầu tiên

Đội phát triển thường bắt đầu bằng câu “dùng channel hay mutex”. Câu hỏi trước đó phải là ai sở hữu dữ liệu và công việc cần chồng lấp ở đâu. Counter chia sẻ, queue job và snapshot config có invariant khác nhau nên không nên dùng cùng một khuôn concurrency cho mọi thứ.

## Đi từng bước qua một tình huống

Với counter độc lập, atomic.Add có thể đủ. Với hai field phải cập nhật cùng nhau, mutex giữ invariant. Với producer chuyển payload cho consumer, channel biểu diễn việc bàn giao. Với rất nhiều job cần giới hạn số đang chạy, fixed worker pool hoặc semaphore có thể phù hợp. Chọn từ hành vi cần bảo đảm rồi mới chọn primitive.

## Hiểu cơ chế từ kết quả quan sát

Mỗi thiết kế vẫn phải đi qua create, admit, execute, publish và finish. Admit là quyết định nhận việc dưới capacity; publish là đưa kết quả cho người khác thấy; finish gồm cleanup và xác nhận kết thúc. Cancellation có thể xảy ra ở bất kỳ giai đoạn nào, nên cần biết ai trả token, ai close channel và lỗi được gửi về đâu.

## Khái niệm và mô hình làm việc

Chọn primitive từ ownership và invariant, rồi mới quyết định channel hay lock.

## Cơ chế và những ranh giới cần giữ

Task lifetime: create, admit, execute, publish, cancel, join. Errors đi cùng results hoặc boundary rõ; channel close không mang cause.

## Áp dụng vào hệ thống thật

Counter dùng atomic; cache invariant dùng mutex; bounded work dùng pool; immutable config publish snapshot.

## Những đường lỗi cần hiểu

Mix nhiều primitives không có protocol; “fire and forget” quên errors và shutdown.

## Lần theo bằng chứng khi có sự cố

Vẽ wait-for graph và lifecycle table; test overload, cancellation, partial failure.

## Đánh đổi và giới hạn sử dụng

Synchronous code là baseline tốt; concurrency chỉ khi có work overlap hoặc isolation cần thiết.

## Thực hành, debugging và kết luận

Dựng một timeline caller bỏ cuộc trước khi result được gửi và một timeline dependency treo. Nếu không xác định được đường thoát ở từng điểm chờ, thiết kế chưa hoàn chỉnh. Đừng dùng concurrency chỉ để tăng số goroutine: đo latency, throughput và chi phí memory, giữ giải pháp tuần tự khi nó đã đáp ứng yêu cầu.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
