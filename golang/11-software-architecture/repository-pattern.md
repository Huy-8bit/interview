# Repository theo use case

## Bài toán và ví dụ đầu tiên

Service cần lưu order nhưng không nên biết placeholder SQL hoặc cách Scan. Repository đặt boundary truy cập dữ liệu theo hành vi domain, giúp business code tập trung vào rule.

## Đi từng bước qua một tình huống

Method ReserveStock(ctx, productID, quantity) có thể biểu đạt conditional update và báo thiếu hàng rõ hơn generic Update(table,map). Khi nhiều method phải cùng transaction, repository API cần cho use case giữ transaction boundary mà không gọi DB ngoài Tx vô ý.

## Hiểu cơ chế từ kết quả quan sát

Repository fake hữu ích cho unit test nhưng không chứng minh isolation/query/index. Không trả Rows ra service nếu muốn repository sở hữu connection lifetime; map kết quả có bound rồi close trong adapter khi phù hợp. Error not-found/duplicate nên có contract ổn định thay vì leak text driver.

## Khái niệm và mô hình làm việc

Repository che storage mechanics khi domain cần persistence contract ổn định.

## Cơ chế và những ranh giới cần giữ

Prefer GetOrder/ReserveStock transaction-aware operations thay generic CRUD đủ mọi table. Return structs khi implementation/API phù hợp; accept small interfaces tại consumer.

## Áp dụng vào hệ thống thật

Store atomic method thực hiện conditional UPDATE và affected-row check.

## Những đường lỗi cần hiểu

Repository trả ORM session ra service; generic interface không biểu diễn transaction và locking.

## Lần theo bằng chứng khi có sự cố

Integration test invariant, SQL shape và cancellation; mock không chứng minh isolation.

## Đánh đổi và giới hạn sử dụng

Reporting queries có thể dùng SQL trực tiếp trong adapter thay ép aggregate repository.

## Thực hành, debugging và kết luận

Test repository với DB thật cho constraints, null và concurrent updates. Đo query count để boundary không che N+1. Tránh abstraction generic quá rộng khiến use case không thể dùng query cần thiết hoặc reviewer không thấy SQL tốn kém ở đâu.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Thực hành có điều kiện kiểm chứng

So Reserve(ctx,itemID,n) atomic với Get→Set stock qua hai methods. Bản thứ hai buộc service biết transaction/locking và dễ oversell nếu fake tests không simulate concurrent callers. Repository tốt expose operation đủ diễn tả invariant, nhưng không nhồi orchestration external provider vào DB adapter. Query-specific read model có thể tách khỏi write repository.
