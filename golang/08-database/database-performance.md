# Database performance bằng query evidence

## Bài toán và ví dụ đầu tiên

Endpoint list orders chậm có thể do chờ pool, scan table, lock wait, trả quá nhiều rows hoặc encode JSON. “DB chậm” là kết luận quá rộng nếu không chia thời gian theo các pha đó.

## Đi từng bước qua một tình huống

Đo số query/request và timeline acquire→execute→consume. Query execution 10 ms nhưng consume 2 giây do application đọc chậm vẫn giữ connection lâu. Một query nhanh đơn lẻ lặp 101 lần trong một endpoint cũng có thể tạo latency lớn vì round trips.

## Hiểu cơ chế từ kết quả quan sát

Query plan cho biết cách engine tiếp cận dữ liệu theo estimates; estimates lệch do distribution/statistics có thể dẫn tới plan không phù hợp. Index phải khớp predicate/order/join và có write/storage cost. Pagination cần bound kết quả để không dồn toàn bộ table vào memory Go.

## Khái niệm và mô hình làm việc

Latency DB gồm acquire, network, execution, lock waits và result consumption.

## Cơ chế và những ranh giới cần giữ

Index cần match filters/order; selective composite indexes khác independent single indexes. EXPLAIN ANALYZE thực thi query, BUFFERS cho IO/cache clues; cập nhật statistics theo data churn.

## Áp dụng vào hệ thống thật

Keyset pagination trên (created_at,id), bounded result columns và batch writes theo commit budget.

## Những đường lỗi cần hiểu

Unselective index không giúp; N+1, hot rows, stale stats, autovacuum pressure và long snapshots.

## Lần theo bằng chứng khi có sự cố

Query fingerprint + latency distributions, waits, plans và cardinality estimate errors; test realistic data volume.

## Đánh đổi và giới hạn sử dụng

Index tăng read performance nhưng thêm write/storage cost; không index mọi column.

## Thực hành, debugging và kết luận

So p 95/p99 theo normalized query và cùng parameter distribution. Kiểm tra lock waits trước khi thêm index; index không mở khóa một transaction giữ row. Với EXPLAIN ANALYZE, chọn môi trường và query an toàn vì nó thực thi công việc. Xác nhận sửa bằng load đại diện và pool wait giảm thật.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/database/)
