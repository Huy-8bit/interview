# Transactions và short critical sections

## Bài toán và ví dụ đầu tiên

Chuyển tiền phải giảm tài khoản A và tăng tài khoản B cùng nhau. Nếu process lỗi sau bước đầu, hai lệnh độc lập để lại dữ liệu sai. Transaction gom các operation trong một durable boundary có commit hoặc rollback theo hệ quản trị.

## Đi từng bước qua một tình huống

BeginTx lấy connection cho transaction, defer rollback cleanup, thực hiện các câu lệnh qua tx rồi Commit nếu mọi bước hợp lệ. Rollback sau Commit thành công chỉ phục vụ cleanup pattern và lỗi already done được xử lý theo policy. Đừng gọi db.Exec giữa Tx rồi nghĩ lệnh đó nằm trong transaction.

## Hiểu cơ chế từ kết quả quan sát

Transaction giữ connection và có thể giữ locks lâu. Gọi external HTTP khi transaction mở làm network latency trở thành lock hold time. Commit trả lỗi do mất kết nối có thể để caller không biết outcome; không mặc định rollback đã xảy ra. Operation ID và truy vấn trạng thái durable giúp reconciliation.

## Khái niệm và mô hình làm việc

Transaction bảo vệ durable invariant trên nhiều operations; connection bị giữ từ Begin tới Commit/Rollback.

## Cơ chế và những ranh giới cần giữ

Dùng tx cho mọi query thuộc operation, validate trước khi begin khi có thể, lock rows theo thứ tự, xử lý commit error. Retry serialization failure cho whole transaction với budget.

## Áp dụng vào hệ thống thật

Debit-credit cùng DB transaction; publish event qua outbox trong cùng commit.

## Những đường lỗi cần hiểu

External HTTP call trong Tx kéo lock; retry chỉ statement cuối trên aborted Tx sai.

## Lần theo bằng chứng khi có sự cố

Xem transaction age, lock wait, SQLSTATE và rollback paths; inject error giữa từng statement.

## Đánh đổi và giới hạn sử dụng

Short Tx giảm contention; chia Tx có thể phá atomicity nên phải định nghĩa saga khi khác DB.

## Thực hành, debugging và kết luận

Test lỗi từng bước và concurrent transactions tác động cùng row. Deadlock/serialization failure cần retry toàn transaction từ input ổn định theo policy, không chỉ câu SQL cuối. Giữ transaction ngắn nhưng đủ bao toàn invariant; chia quá nhỏ để giảm lock có thể làm mất atomicity cần thiết.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/database/)
