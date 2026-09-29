# SQL từ pool connection tới invariant durable

Đọc database/sql và pool trước transaction/driver. Pool wait có thể chiếm hết deadline trước khi SQL tới DB; Rows/Tx lifecycle quyết định lúc trả connection. Sau đó dùng PostgreSQL isolation/constraints và query plans để nối correctness với performance dưới concurrent requests.

## Bắt đầu và cách thực hành

Bắt đầu với [database-sql](database-sql.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Connection exhaustion runbook](connection-exhaustion.md) | P1 |
| [Database performance bằng query evidence](database-performance.md) | P1 |
| [Database connection pool: 500 requests và 20 connections](database-sql-pool.md) | P0 |
| [database/sql: pool handle, rows và transaction ownership](database-sql.md) | P0 |
| [Isolation levels trong PostgreSQL](isolation-levels.md) | P1 |
| [N+1 queries](n-plus-one.md) | P1 |
| [ORM, raw SQL và query ownership](orm-vs-raw-sql.md) | P1 |
| [pgx native và database/sql adapter](pgx.md) | P1 |
| [PostgreSQL với Go](postgres-with-go.md) | P1 |
| [Prepared statements và session scope](prepared-statements.md) | P1 |
| [sqlc: SQL làm contract](sqlc.md) | P1 |
| [Transactions và short critical sections](transactions.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
