# Prepared statements và session scope

## Bài toán và ví dụ đầu tiên

Một API thực hiện cùng dạng query nhiều lần với ID khác nhau. Prepared statement cho DB/driver tái dùng một phần công việc chuẩn bị theo cơ chế của nó; parameterization tách dữ liệu khỏi cú pháp SQL và là nền tảng chống SQL injection.

## Đi từng bước qua một tình huống

Với SELECT ... WHERE id=$1, ID được bind làm dữ liệu thay vì nối vào query string. Tên bảng/cột không thể thay bằng value placeholder tùy ý; identifier động cần allowlist và xây query có kiểm soát. Prepare một lần không có nghĩa chỉ tồn tại một server statement khi pool có nhiều connection.

## Hiểu cơ chế từ kết quả quan sát

Statement có lifecycle gắn DB/Conn/Tx theo API; cache statement và plan behavior phụ thuộc driver/DB. Quá nhiều query shapes hoặc prepare per-request có thể tạo overhead. Generic/custom plan có trade-off với parameter distribution, nên prepare không đảm bảo mọi query nhanh hơn.

## Khái niệm và mô hình làm việc

Prepared statements tái sử dụng parse/plan; parameters tách data khỏi SQL syntax.

## Cơ chế và những ranh giới cần giữ

database/sql Stmt có thể prepare trên nhiều underlying connections; driver/server cache và transaction pooling proxy có compatibility riêng. Close explicit Stmt khi owner kết thúc.

## Áp dụng vào hệ thống thật

Hot fixed query nhiều calls; dynamic filters vẫn cần bounded query shapes.

## Những đường lỗi cần hiểu

Hàng nghìn query shapes phình cache; plan generic kém cho skew; proxy mode làm session assumptions sai.

## Lần theo bằng chứng khi có sự cố

So query plan, prepare rate, cache cardinality và proxy configuration; benchmark realistic parameter distribution.

## Đánh đổi và giới hạn sử dụng

Không prepare mọi one-off query; parameterization vẫn cần dù không explicit Prepare.

## Thực hành, debugging và kết luận

Đo parse/plan/execution và số statements trên workload thật. Test qua pooler/proxy nếu có vì session versus transaction pooling ảnh hưởng assumptions. Close statement theo owner khi không còn dùng và ưu tiên parameterization ngay cả khi không dùng explicit Prepare.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/database/)
