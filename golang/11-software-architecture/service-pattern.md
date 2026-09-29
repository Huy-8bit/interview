# Service giữ business orchestration

## Bài toán và ví dụ đầu tiên

Handler tạo order cần kiểm tra quyền, tính tổng và phối hợp repository/payment. Nếu nhét mọi thứ vào handler, cùng use case gọi từ consumer phải copy logic. Service/use-case layer điều phối nghiệp vụ với input/output có nghĩa.

## Đi từng bước qua một tình huống

Service nhận dependencies ở constructor, ctx và input ở mỗi operation. Nó quyết định transaction boundary và lỗi domain; HTTP adapter map lỗi thành response, consumer adapter map thành retry/DLQ theo semantics. Không để service tự ghi ResponseWriter vì điều đó gắn core vào HTTP lifetime.

## Hiểu cơ chế từ kết quả quan sát

Orchestration cần giữ thứ tự side effects và failure state. Gọi payment trước/ sau DB commit có cửa sổ khác nhau; một method tên CreateOrder không tự atomic qua network. Service không nên thành god object chứa mọi domain vì reuse constructor tiện.

## Khái niệm và mô hình làm việc

Service phối hợp dependencies và invariant một use case; không phải singleton global chứa mọi state.

## Cơ chế và những ranh giới cần giữ

Constructor nhận explicit stores/clients/clock; method nhận context và command typed. Error mapping HTTP ở adapter.

## Áp dụng vào hệ thống thật

Checkout ghi order/outbox trong một transaction rồi trả accepted state.

## Những đường lỗi cần hiểu

Service giữ request ctx trong field; gọi external provider giữa DB transaction.

## Lần theo bằng chứng khi có sự cố

Test failure từng boundary và review resource ownership trong constructor/lifecycle.

## Đánh đổi và giới hạn sử dụng

Stateless service dễ share; mutable cache cần synchronization riêng.

## Thực hành, debugging và kết luận

Test timeline dependency lỗi từng bước và assert side effects nào được phép xảy ra. Fake clock/provider giúp kiểm soát, integration test adapter giữ contract. Khi service chỉ forward repository cho CRUD nhỏ, một lớp mỏng có thể chấp nhận nhưng không cần thêm framework orchestration.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Thực hành có điều kiện kiểm chứng

Service method Checkout nhận typed command và ctx, trả order ID/state/error; HTTP status mapping ở handler. Khi provider call timeout sau possible charge, service trả/persist unknown state thay báo failed chắc chắn. Business tests dùng fake provider có ambiguous outcome; infrastructure tests kiểm request deadlines và body cleanup. Điều này giữ domain semantics rõ hơn pass-through wrappers.
