# Layered architecture và vertical features

## Bài toán và ví dụ đầu tiên

Handler vừa parse JSON, tính giá, build SQL và gọi email khiến test nghiệp vụ cần dựng cả HTTP/database. Layered architecture chia trách nhiệm để thay transport hoặc storage mà không viết lại toàn business flow.

## Đi từng bước qua một tình huống

Handler validate hình thức request và map response; service quyết định use case; repository thực hiện truy cập dữ liệu. Service nhận dependency qua constructor và ctx theo từng call. Error domain được map ra HTTP ở boundary thay vì repository biết status code.

## Hiểu cơ chế từ kết quả quan sát

Layering hữu ích khi dependency đi theo hướng rõ, nhưng lớp chỉ forward mọi method không thêm nghĩa có thể làm code dài hơn mà không dễ hiểu. Transaction boundary phải nằm nơi bao đủ invariant; tách repository methods không được làm mất khả năng thực hiện cùng transaction.

## Khái niệm và mô hình làm việc

Layering tổ chức responsibility; dependency direction cần rõ hơn số thư mục.

## Cơ chế và những ranh giới cần giữ

Handler parse/auth/map errors; service giữ invariant; store queries. Packages theo domain giảm cross-feature imports.

## Áp dụng vào hệ thống thật

user/ có service/store contract và adapters theo độ lớn, không bắt đầu bằng hàng chục global layers.

## Những đường lỗi cần hiểu

Handler gọi ORM bypass service; service chỉ pass-through khiến abstraction không thêm giá trị.

## Lần theo bằng chứng khi có sự cố

Review transaction boundaries và import cycles; map change impact của một feature.

## Đánh đổi và giới hạn sử dụng

Small CRUD có thể gộp layers nếu contract vẫn rõ; đừng thêm layer rỗng.

## Thực hành, debugging và kết luận

Test service bằng fake đủ contract và integration test adapter SQL thật. Khi debug incident, trace vẫn phải xuyên các layer với operation ID/context. Chọn số lớp theo độ phức tạp use case, đừng tạo mọi lớp cho một CRUD nhỏ chỉ để khớp sơ đồ.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Thực hành có điều kiện kiểm chứng

Use case create order cần validate business rule, reserve local inventory và insert outbox cùng transaction. Nếu mỗi repository method tự Begin/Commit, service layer nhìn đẹp nhưng không còn atomicity. Truyền transaction-scoped store hoặc đặt atomic operation tại persistence boundary; tests kiểm lỗi statement thứ hai không để lại nửa state. Đừng thêm layer để che boundary bị sai.
