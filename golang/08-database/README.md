# Database

Giữ durable invariants và quản connection lifecycle.

## Reading map

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

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
