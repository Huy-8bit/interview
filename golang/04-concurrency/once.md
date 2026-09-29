# sync.Once và initialization

## Bài toán và ví dụ đầu tiên

Một bảng lookup bất biến cần được parse lần đầu và dùng chung cho mọi request. Hai request đến cùng lúc không nên parse hai bản rồi publish dở dang. sync.Once cho một initializer chạy đúng một lần và các caller khác chờ việc khởi tạo đó hoàn tất.

## Đi từng bước qua một tình huống

A gọi Do(initTable), B gọi cùng Once trong lúc A chạy. B không được coi bảng là ready chỉ vì initializer đã bắt đầu; B chờ hoàn tất rồi đọc kết quả đã công bố. Nếu initializer gọi Do trên chính Once, nó có thể tự chờ mình. Nếu initializer panic, Once vẫn coi lần gọi đó đã thực hiện; không có retry tự động.

## Hiểu cơ chế từ kết quả quan sát

Once phù hợp dữ liệu bất biến có lifetime process. Đưa network fetch dễ thất bại tạm thời vào Once có thể cache trạng thái lỗi vĩnh viễn. Nếu cần retry, dùng state machine có trạng thái chưa tải/đang tải/ready/lỗi và chính sách thử lại rõ, hoặc khởi tạo ở startup rồi fail readiness nếu không thành công.

## Khái niệm và mô hình làm việc

Once bảo đảm function chạy một lần và completion được publish cho các callers.

## Cơ chế và những ranh giới cần giữ

Panic trong initializer vẫn đánh dấu Once đã thực hiện; retry cần state machine riêng. Recursive Do trên cùng Once deadlock.

## Áp dụng vào hệ thống thật

Lazy immutable lookup table hoặc expensive parse; constructor eager thường rõ hơn cho config có thể fail.

## Những đường lỗi cần hiểu

Transient network failure trong Once bị cache vĩnh viễn; copied Once phá lifecycle.

## Lần theo bằng chứng khi có sự cố

Reproduce initializer failure/panic, xem readiness và callers đợi Do.

## Đánh đổi và giới hạn sử dụng

Không dùng Once cho secret refresh hoặc reconnect cần retry.

## Thực hành, debugging và kết luận

Khi startup treo, lấy stack caller chờ Do và initializer đang giữ tài nguyên gì. Test cả success, error và panic theo contract của wrapper bạn viết. Eager constructor thường dễ hiểu hơn lazy Once khi cấu hình bắt buộc phải hợp lệ trước khi server nhận request. Không copy Once đang dùng sang object khác.


## Đọc tiếp

- [Channel internals và synchronization](channels.md)
- [Mutex: invariants, contention và lock ownership](mutex.md)
- [cancellation](../05-context/cancellation.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/sync)

## Thực hành có điều kiện kiểm chứng

Tạo initializer fail lần đầu rồi thành công ở lần hai. Với Once, lần hai không gọi lại initializer; test phải phản ánh đây là contract, không kết luận thư viện lỗi. Nếu cần retry, thiết kế state uninitialized/initializing/ready/failed với một owner, result/error publication và waiters có cancellation. Initialization network call cần deadline để không giữ tất cả callers chờ Do.
