# Lab 09 · Expression index: lower(username)

## Objective

Hiểu **expression index**: index lưu kết quả của một biểu thức và chỉ được dùng khi query viết đúng biểu thức đó.

## Problem

Đăng nhập không phân biệt hoa thường: `WHERE lower(username) = lower(?)`. Cột `username` có index
UNIQUE thường, nhưng query vẫn Seq Scan 5 triệu dòng. Tương tự, tìm theo `email = ?` không dùng
được index `ux_users_email_lower` vì index đó được tạo trên `lower(email)`.

## Baseline Query

Q1 — Case-insensitive login by username

```sql
SELECT id, username, email
FROM users
WHERE lower(username) = lower('Sarah.Brown2037');
```

Q2 — Exact username (matches the plain index)

```sql
SELECT id, username, email
FROM users
WHERE username = 'sarah.brown2037';
```

Q3 — Email compared WITHOUT lower()

```sql
SELECT id, username, email
FROM users
WHERE email = 'sarah.brown2037@gmail.com';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Gather  (cost=1000.00..284953.31 rows=25002 width=58) (actual time=455.759..458.510 rows=1 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   Buffers: shared hit=224 read=249976
   ->  Parallel Seq Scan on users  (cost=0.00..281453.11 rows=10418 width=58) (actual time=308.299..448.986 rows=0 loops=3)
         Filter: (lower((users.username)::text) = 'sarah.brown2037'::text)
         Rows Removed by Filter: 1666666
         Buffers: shared hit=224 read=249976
 Planning Time: 0.049 ms
 Execution Time: 458.637 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Gather
  └── Parallel Seq Scan on users
        Filter: (lower(username) = 'sarah.brown2037')
```
Index `uq_users_username` chứa giá trị `username` gốc. PostgreSQL không thể suy ra
`lower(username)` từ thứ tự của `username` (chữ hoa/thường sắp khác nhau), nên phải tính
`lower()` cho từng dòng.

## Bottleneck

Seq Scan + tính `lower()` cho 5 triệu dòng để tìm 1 dòng.

## Optimization Strategy A

**Expression index on lower(username)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab09_users_username_lower ON users (lower(username));
ANALYZE users;
```

## Result

AFTER Strategy A — Q1:

```text
 Index Scan using ix_lab09_users_username_lower on users  (cost=0.56..2.78 rows=1 width=58) (actual time=0.004..0.004 rows=1 loops=1)
   Index Cond: (lower((users.username)::text) = 'sarah.brown2037'::text)
   Buffers: shared hit=5
 Planning Time: 0.007 ms
 Execution Time: 0.005 ms
```

Q1: `Index Scan using ix_lab09_users_username_lower`. Q2 không đổi. Q3 (email không lower) vẫn Seq Scan.

## Why It Improved

Index `ON users (lower(username))` lưu sẵn kết quả `lower(username)` đã sắp xếp: query
`lower(username) = ...` thành Index Scan, ~micro giây. ANALYZE còn thu thập statistics cho
biểu thức (xem `pg_stats` với `tablename = 'ix_lab09_users_username_lower'`), nên ước lượng
số dòng cũng chính xác.

## Trade-offs

- Index thêm ~196 MB; mỗi INSERT/UPDATE username phải tính `lower()` và cập nhật index.
- Hàm trong index phải `IMMUTABLE` (Lab 10 cho thấy lỗi khi không phải).
- Query phải viết **đúng** biểu thức: `lower(username)` dùng được, `upper(username)` hay
  `username ILIKE ...` thì không.

## Optimization Strategy B

**No DDL: rewrite the email query to match the existing lower(email) index** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Index Scan using ux_users_email_lower on users  (cost=0.56..2.78 rows=1 width=58) (actual time=0.004..0.004 rows=1 loops=1)
   Index Cond: (lower((users.email)::text) = 'sarah.brown2037@gmail.com'::text)
   Buffers: shared hit=5
 Planning Time: 0.008 ms
 Execution Time: 0.006 ms
```

Không cần DDL: viết lại Q3 thành `lower(email) = lower(...)` dùng ngay index `ux_users_email_lower` có
sẵn — và đó cũng là cách so sánh đúng về nghiệp vụ (email không phân biệt hoa thường; ~5% email trong
dataset có chữ hoa).

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Case-insensitive login by username**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Seq Scan on public.users` | 1 | 1,666,666 | shared hit=224 read=249976 | 458.6 ms |
| Strategy A | `Index Scan using ix_lab09_users_username_lower on public.users` | 1 | 0 | shared hit=5 | 0.005 ms |

**Q2 — Exact username (matches the plain index)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using uq_users_username on public.users` | 1 | 0 | shared hit=5 | 0.008 ms |
| Strategy A | `Index Scan using uq_users_username on public.users` | 1 | 0 | shared hit=5 | 0.011 ms |

**Q3 — Email compared WITHOUT lower()**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Seq Scan on public.users` | 1 | 1,666,666 | shared hit=513 read=249687 | 207.1 ms |
| Strategy A | `Parallel Seq Scan on public.users` | 1 | 1,666,666 | shared hit=929 read=249271 | 147.4 ms |

**Strategy B — No DDL: rewrite the email query to match the existing lower(email) index**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Email lookup rewritten as lower(email) = lower(...) | `Index Scan using ux_users_email_lower on public.users` | 1 | 0 | shared hit=5 | 0.006 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab09_users_username_lower;
-- (nothing to undo: query rewrite only)
ANALYZE users;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Filter: (lower(...) = ...)` trên Seq Scan → thiếu expression index hoặc query không khớp biểu thức index.
- `Index Cond: (lower((username)::text) = ...)` → index biểu thức được dùng.

## Interview Questions

1. Expression index là gì? Khi nào planner dùng nó?
2. Vì sao hàm trong expression index phải IMMUTABLE?
3. So sánh expression index lower(email) với kiểu citext hoặc collation không phân biệt hoa thường.
4. Statistics của expression index nằm ở đâu?

## Key Takeaways

- Một hàm bọc quanh cột làm index thường của cột đó vô dụng cho điều kiện ấy.
- Expression index giải quyết bằng cách index chính biểu thức.
- Trước khi tạo index mới, kiểm tra xem viết lại query có dùng được index sẵn có không.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`02b_strategy_b.sql`](02b_strategy_b.sql) | Strategy B |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
