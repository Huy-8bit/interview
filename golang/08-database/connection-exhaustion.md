# Connection exhaustion runbook

## Bài toán và ví dụ đầu tiên

Sau release, mọi request chờ SQL dù PostgreSQL CPU thấp. DB.Stats cho InUse bằng MaxOpenConns và WaitCount tăng. Exhaustion nghĩa demand không lấy được slot trong budget; gốc có thể là slow query, transaction dài, Rows không Close hoặc cấu hình vượt budget fleet.

## Đi từng bước qua một tình huống

Một handler mở Rows rồi gọi external service trước khi iterate xong. Connection bị giữ cả thời gian network. Khi nhiều handler cùng làm vậy, pool đầy dù query ban đầu nhanh. Đưa phần network ra ngoài lifetime Rows/Tx nếu semantics cho phép và bảo đảm Close trên đường lỗi.

## Hiểu cơ chế từ kết quả quan sát

Pool wait khác execution time. Tăng max open có thể đẩy pressure xuống DB và tăng số query concurrent vượt capacity. Một nested DB call trong Tx khi pool đã hết slot còn có thể tạo vòng chờ cục bộ. Context giới hạn chờ nhưng không sửa cấu trúc ownership.

## Khái niệm và mô hình làm việc

Exhaustion là demand hoặc hold time vượt pool/server budget, không chỉ config nhỏ.

## Cơ chế và những ranh giới cần giữ

Rows, Tx, dedicated Conn và downstream lock waits đều có thể giữ slot; fleet pool count phải có reserve cho admin/migrations.

## Áp dụng vào hệ thống thật

Giới hạn API admission và worker concurrency riêng; pool acquire timeout ngăn chờ vô hạn.

## Những đường lỗi cần hiểu

Long idle-in-transaction; retry storm; HPA tăng pods; leak cleanup.

## Lần theo bằng chứng khi có sự cố

Stats InUse/Wait deltas, pg_stat_activity, blockers và transaction age; lấy goroutine stacks cùng lúc.

## Đánh đổi và giới hạn sử dụng

Mitigate giảm intake/retries trước tăng DB connections khi chưa biết headroom.

## Thực hành, debugging và kết luận

Bắt đầu bằng stats theo cửa sổ, goroutine stacks và pg_stat_activity cùng timestamp. So active transactions/rows với traffic và release diff. Mitigate bằng giảm admission hoặc rollback lỗi, rồi test leak/slow path; không chỉ tăng pool rồi bỏ theo dõi latency DB.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/database/)
