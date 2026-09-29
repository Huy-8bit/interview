# Clean Architecture theo tinh thần Go

## Bài toán và ví dụ đầu tiên

Business rule tính phí không nên thay đổi vì chuyển framework HTTP. Clean architecture định hướng dependency vào policy ổn định hơn, để chi tiết I/O đứng ở adapter bên ngoài.

## Đi từng bước qua một tình huống

Use case phụ thuộc interface như OrderStore do nhu cầu use case định nghĩa; SQL adapter implement interface đó. Main lắp adapter vào service. Domain type không cần import database/sql hay net/http chỉ để lưu/transport được dữ liệu.

## Hiểu cơ chế từ kết quả quan sát

Dependency inversion không có nghĩa interface cho mọi struct. Interface nhỏ giúp thay implementation khi thực sự có boundary; abstraction quá generic có thể giấu query semantics và transaction. DTO của transport và domain state có thể khác để tránh client sửa field không được phép.

## Khái niệm và mô hình làm việc

Dependency direction bảo vệ business policy khỏi transport/storage; không bắt buộc nhiều layer/class như Java.

## Cơ chế và những ranh giới cần giữ

Domain package có concrete types và small consumer interfaces. Adapter implement implicit interface; cmd compose dependencies explicit.

## Áp dụng vào hệ thống thật

Order service nhận Store interface gồm operations business cần, không mirror toàn ORM.

## Những đường lỗi cần hiểu

Interface mọi struct, DTO mapping lặp và generic base repository che transaction semantics.

## Lần theo bằng chứng khi có sự cố

Trace một use case qua imports; nếu thay HTTP làm domain đổi thì boundary chưa đúng.

## Đánh đổi và giới hạn sử dụng

Abstraction cần lợi ích test/substitution; một package rõ thường tốt hơn nhiều layer rỗng.

## Thực hành, debugging và kết luận

Đánh giá bằng việc test rule không mở network và thay adapter có phạm vi rõ. Khi performance cần query đặc thù, cho repository method biểu đạt đúng use case thay vì cố nhét vào CRUD chung. Trade-off là thêm mapping và indirection; chỉ giữ phần mang lại isolation cần thiết.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)
