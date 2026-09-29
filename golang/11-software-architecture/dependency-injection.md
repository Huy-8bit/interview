# Explicit dependency injection

## Bài toán và ví dụ đầu tiên

Test tính giá cần dùng thời gian cố định nhưng code gọi time.Now và global DB ở nhiều chỗ. Dependency injection cung cấp các thành phần từ bên ngoài để behavior có thể được cấu hình và kiểm chứng rõ.

## Đi từng bước qua một tình huống

Constructor nhận repository, clock function và HTTP client phù hợp, validate dependency bắt buộc rồi trả service. Main là nơi lắp implementation thật; test cung cấp fake có semantics cần. Context không là nơi giấu dependencies dài hạn vì nó thuộc từng operation/request.

## Hiểu cơ chế từ kết quả quan sát

Explicit constructor làm graph dễ đọc và lifecycle owner rõ: ai tạo DB thì thường chịu Close ở cấp application. Interface chỉ cần ở boundary cần thay thế; inject concrete pointer vẫn là injection. Container reflection có thể giảm wiring nhưng chuyển một số lỗi sang runtime.

## Khái niệm và mô hình làm việc

Go constructor wiring làm dependency và lifecycle nhìn thấy tại startup.

## Cơ chế và những ranh giới cần giữ

Main tạo config, logger, pool, clients, service, handlers; shutdown theo thứ tự ngược dependency use. Small interface chỉ ở boundary cần test/substitution.

## Áp dụng vào hệ thống thật

NewService(store, clock) cho test deterministic time.

## Những đường lỗi cần hiểu

Global DB làm test tranh chấp; reflection container lỗi runtime; dependency optional mơ hồ typed nil.

## Lần theo bằng chứng khi có sự cố

Compile-time interface assertions và startup validation; tests explicit fake dependencies.

## Đánh đổi và giới hạn sử dụng

Manual DI dễ đọc cho đa số services; generator có ích khi graph thật lớn.

## Thực hành, debugging và kết luận

Test constructor thiếu dependency và kiểm tra shutdown đóng đúng sau workers. Không inject mọi constant chỉ để gọi là testable; chọn những thứ có behavior/IO/time cần kiểm soát. Với project Go vừa phải, wiring tường minh thường đủ dễ bảo trì.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Thực hành có điều kiện kiểm chứng

Wiring order minh họa: load validated config→logger→DB pool→provider client→payment service→HTTP handler. Shutdown đảo quan hệ sử dụng: stop/drain handlers và workers trước close DB/client. Constructor không nên âm thầm start goroutine mà không trả owner có Close/Wait contract. Unit tests inject clock/fake provider, integration tests giữ adapter thật.
