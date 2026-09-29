# DDD: invariants và bounded contexts

## Bài toán và ví dụ đầu tiên

Từ “order” có thể nghĩa khác ở checkout và fulfillment. Nếu ép một struct Order khổng lồ phục vụ mọi nơi, thay đổi của một nhóm dễ phá nhóm khác. DDD bắt đầu từ ngôn ngữ nghiệp vụ và boundary nơi thuật ngữ có nghĩa nhất quán.

## Đi từng bước qua một tình huống

Bounded context là phạm vi mô hình/ngôn ngữ đó. Aggregate là nhóm state giữ invariant qua một boundary cập nhật, ví dụ order và các line items theo rule tổng tiền. Aggregate không mặc nhiên là một service hoặc một bảng; chọn từ operation cần đúng cùng nhau.

## Hiểu cơ chế từ kết quả quan sát

Value object biểu diễn giá trị có semantics như Money(currency,minorUnits); entity có identity qua thời gian. Repository mô tả lưu/lấy aggregate theo use case, không nhất thiết expose mọi query của UI. Event cần chỉ rõ fact đã xảy ra thay vì lệnh người nhận phải làm.

## Khái niệm và mô hình làm việc

DDD giúp ngôn ngữ nghiệp vụ và consistency boundary rõ; không bắt buộc aggregate cho mọi row.

## Cơ chế và những ranh giới cần giữ

Aggregate bảo vệ invariant trong transaction boundary; domain event nêu fact đã xảy ra. Bounded context có model riêng, mapping ở integration boundary.

## Áp dụng vào hệ thống thật

Payment ledger khác order fulfillment; saga điều phối giữa contexts.

## Những đường lỗi cần hiểu

Aggregate quá lớn gây lock contention; event phát trước commit; dùng một User model toàn công ty.

## Lần theo bằng chứng khi có sự cố

Hỏi invariant cần atomic ở đâu và domain experts gọi trạng thái thế nào.

## Đánh đổi và giới hạn sử dụng

DDD hữu ích domain phức tạp; CRUD đơn giản không cần ceremony.

## Thực hành, debugging và kết luận

Làm việc từ một rule cụ thể và failure case, không thêm thuật ngữ để trang trí. Test invariant như không giao order chưa thanh toán. DDD có chi phí mô hình hóa; với CRUD đơn giản, type và service rõ có thể đủ mà chưa cần nhiều pattern.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)
