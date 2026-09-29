# Condition variable và predicate

## Bài toán và ví dụ đầu tiên

Một resource manager có nhiều điều kiện: đã có buffer và hệ thống chưa đóng. sync.Cond cho goroutine chờ một predicate, tức điều kiện về shared state, trong khi giải phóng lock để bên khác thay đổi state.

## Đi từng bước qua một tình huống

Goroutine Lock, kiểm tra điều kiện trong for rồi gọi Wait nếu chưa đạt. Wait giải phóng lock và đưa goroutine vào chờ; trước khi return nó lấy lại lock. Sau khi tỉnh phải kiểm tra lại vì waiter khác có thể đã lấy resource. Dùng if khiến một goroutine tiếp tục với điều kiện không còn đúng.

## Hiểu cơ chế từ kết quả quan sát

Signal đánh thức một waiter; Broadcast đánh thức tất cả để mỗi bên tự kiểm tra state. Notification không được lưu như message trong queue. Nếu Signal xảy ra khi chưa có waiter, một waiter tới sau vẫn phải quyết định từ state được bảo vệ bởi lock. State là nguồn sự thật, signal chỉ là lời nhắc kiểm tra.

## Khái niệm và mô hình làm việc

sync.Cond chờ predicate của shared state dưới lock, không giữ lịch sử events như queue.

## Cơ chế và những ranh giới cần giữ

Lock, kiểm tra predicate trong for, Wait atomically unlock/park rồi reacquire trước return. Signal wake một waiter; Broadcast wake tất cả để họ kiểm tra lại predicate.

## Áp dụng vào hệ thống thật

Bounded resource manager có điều kiện phức tạp mà channel không biểu diễn dễ.

## Những đường lỗi cần hiểu

Signal trước waiter nhưng predicate không được lưu gây lost notification; dùng if thay for sai khi waiter khác lấy resource trước.

## Lần theo bằng chứng khi có sự cố

Vẽ predicate transitions dưới cùng lock và waiters; test multiple consumers.

## Đánh đổi và giới hạn sử dụng

Không có direct context select với Cond; channel thường dễ lifecycle hơn.

## Thực hành, debugging và kết luận

Debug bằng việc liệt kê mọi thay đổi predicate và bảo đảm chúng dùng cùng lock. Test nhiều waiter cạnh tranh một resource và shutdown Broadcast đánh thức người chờ. Cond không có ctx.Done trực tiếp; bridging cancellation cần tránh missed wakeup và quản lý callback. Nếu chỉ chuyển từng job, channel thường biểu diễn ownership đơn giản hơn.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)
