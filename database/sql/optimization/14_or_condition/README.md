# Lab 14 · OR conditions: BitmapOr, missing index, OR across a join

## Objective

Hiểu cách PostgreSQL xử lý `OR`: BitmapOr giữa các index, khi nào OR buộc phải Seq Scan, và viết lại OR giữa hai bảng bằng `UNION`.

## Problem

Tìm user theo email **hoặc** username (giống `sql/query/find-user.sql`), theo email **hoặc** số điện
thoại, và tìm đơn theo số đơn **hoặc** username người mua.

## Baseline Query

Q1 — OR of two indexed columns of the same table

```sql
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR username = 'jessica.reyes4242';
```

Q2 — OR where one side has NO index

```sql
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR phone = '+1-236-702-0729';
```

Q3 — OR across two joined tables

```sql
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241218-00250000'
   OR u.username = 'jessica.reyes4242';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Bitmap Heap Scan on users  (cost=3.33..5.57 rows=2 width=58) (actual time=0.008..0.009 rows=2 loops=1)
   Recheck Cond: ((lower((users.email)::text) = 'sarah.brown2037@gmail.com'::text) OR ((users.username)::text = 'jessica.reyes4242'::text))
   Heap Blocks: exact=2
   Buffers: shared hit=10
   ->  BitmapOr  (cost=3.33..3.33 rows=2 width=0) (actual time=0.007..0.007 rows=0 loops=1)
         Buffers: shared hit=8
         ->  Bitmap Index Scan on ux_users_email_lower  (cost=0.00..1.67 rows=1 width=0) (actual time=0.004..0.004 rows=1 loops=1)
               Index Cond: (lower((users.email)::text) = 'sarah.brown2037@gmail.com'::text)
               Buffers: shared hit=4
         ->  Bitmap Index Scan on uq_users_username  (cost=0.00..1.67 rows=1 width=0) (actual time=0.003..0.003 rows=1 loops=1)
               Index Cond: ((users.username)::text = 'jessica.reyes4242'::text)
               Buffers: shared hit=4
 Planning Time: 0.010 ms
 Execution Time: 0.012 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Q1 — mỗi nhánh OR có index riêng:
```text
Bitmap Heap Scan on users
  └── BitmapOr
        ├── Bitmap Index Scan on ux_users_email_lower
        └── Bitmap Index Scan on uq_users_username
```
Q2 — một nhánh không có index: một dòng có thể khớp qua nhánh đó, nên phải đọc mọi dòng → Seq Scan.

Q3 — OR trộn cột của hai bảng: không điều kiện nào đẩy được xuống một bảng →
```text
Parallel Hash Join
  Join Filter: (order_number = '...' OR username = '...')
  Rows Removed by Join Filter: 1666664
  ├── Parallel Seq Scan on orders
  └── Parallel Hash  (Batches: 32)  <- hash 5M users, tràn đĩa
        └── Parallel Seq Scan on users
```

## Bottleneck

Q2: Seq Scan 5M users. Q3: join toàn bộ hai bảng 5M dòng (hash tràn 32 batch) để lấy 7 dòng — 1–2 giây.

## Optimization Strategy A

**Index the missing column (users.phone)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab14_users_phone ON users (phone);
```

## Result

AFTER Strategy A — Q1:

```text
 Bitmap Heap Scan on users  (cost=3.33..5.57 rows=2 width=58) (actual time=0.009..0.009 rows=2 loops=1)
   Recheck Cond: ((lower((users.email)::text) = 'sarah.brown2037@gmail.com'::text) OR ((users.username)::text = 'jessica.reyes4242'::text))
   Heap Blocks: exact=2
   Buffers: shared hit=10
   ->  BitmapOr  (cost=3.33..3.33 rows=2 width=0) (actual time=0.008..0.008 rows=0 loops=1)
         Buffers: shared hit=8
         ->  Bitmap Index Scan on ux_users_email_lower  (cost=0.00..1.67 rows=1 width=0) (actual time=0.004..0.004 rows=1 loops=1)
               Index Cond: (lower((users.email)::text) = 'sarah.brown2037@gmail.com'::text)
               Buffers: shared hit=4
         ->  Bitmap Index Scan on uq_users_username  (cost=0.00..1.67 rows=1 width=0) (actual time=0.003..0.003 rows=1 loops=1)
               Index Cond: ((users.username)::text = 'jessica.reyes4242'::text)
               Buffers: shared hit=4
 Planning Time: 0.015 ms
 Execution Time: 0.014 ms
```

Q2: `BitmapOr` (ux_users_email_lower + ix_lab14_users_phone). Q3 không đổi (vẫn hash join toàn bảng).

## Why It Improved

- Index trên `phone` (Strategy A) → Q2 thành BitmapOr của hai index, ~0.1 ms.
- UNION (Strategy B) → Q3 thành hai Nested Loop nhỏ (mỗi nhánh tra một index, rồi tra bảng kia theo
  khóa), cộng bước khử trùng lặp: từ hơn 1 giây xuống ~0.03 ms.

## Trade-offs

- UNION khử trùng lặp (Sort/HashAggregate) để giữ nghĩa của OR; nếu chắc chắn hai nhánh không trùng
  (hoặc trùng không sao) thì `UNION ALL` rẻ hơn.
- Viết lại thành UNION làm query dài hơn; mỗi nhánh cần index phù hợp.

## Optimization Strategy B

**Rewrite the cross-table OR as UNION (each branch uses its own index)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Unique  (cost=12.61..12.63 rows=2 width=184) (actual time=0.019..0.020 rows=7 loops=1)
   Buffers: shared hit=22
   ->  Sort  (cost=12.61..12.61 rows=2 width=184) (actual time=0.019..0.019 rows=7 loops=1)
         Sort Key: o.id, o.order_number, u.username
         Sort Method: quicksort  Memory: 25kB
         Buffers: shared hit=22
         ->  Append  (cost=0.86..12.60 rows=2 width=184) (actual time=0.007..0.017 rows=7 loops=1)
               Buffers: shared hit=22
               ->  Nested Loop  (cost=0.86..5.30 rows=1 width=48) (actual time=0.007..0.007 rows=1 loops=1)
                     Inner Unique: true
                     Buffers: shared hit=8
                     ->  Index Scan using uq_orders_order_number on orders o  (actual time=0.005..0.005 rows=1 loops=1)
                           Index Cond: ((o.order_number)::text = 'ORD-241218-00250000'::text)
                           Buffers: shared hit=4
                     ->  Index Scan using pk_users on users u  (cost=0.43..2.65 rows=1 width=28) (actual time=0.002..0.002 rows=1 loops=1)
                           Index Cond: (u.id = o.user_id)
                           Buffers: shared hit=4
               ->  Nested Loop  (cost=0.99..7.29 rows=1 width=48) (actual time=0.008..0.010 rows=6 loops=1)
                     Buffers: shared hit=14
                     ->  Index Scan using uq_users_username on users u_1  (actual time=0.007..0.007 rows=1 loops=1)
                           Index Cond: ((u_1.username)::text = 'jessica.reyes4242'::text)
                           Buffers: shared hit=5
                     ->  Index Scan using idx_orders_user_id on orders o_1  (actual time=0.001..0.002 rows=6 loops=1)
                           Index Cond: (o_1.user_id = u_1.id)
                           Buffers: shared hit=9
   Buffers: shared hit=32
 Planning Time: 0.081 ms
 Execution Time: 0.027 ms
```

Q3 viết lại bằng UNION: `Append` của hai Nested Loop dùng index, `Unique` ở trên.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — OR of two indexed columns of the same table**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Bitmap Index Scan on ux_users_email_lower, Bitmap Index Scan on uq_users_username` | 2 | 0 | shared hit=10 | 0.012 ms |
| Strategy A | `Bitmap Index Scan on ux_users_email_lower, Bitmap Index Scan on uq_users_username` | 2 | 0 | shared hit=10 | 0.014 ms |

**Q2 — OR where one side has NO index**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Seq Scan on public.users` | 2 | 1,666,666 | shared hit=195 read=250005 | 569.6 ms |
| Strategy A | `Bitmap Index Scan on ux_users_email_lower, Bitmap Index Scan on ix_lab14_users_phone` | 2 | 0 | shared hit=9 | 0.092 ms |

**Q3 — OR across two joined tables**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Hash Join, Parallel Seq Scan on public.orders o, Parallel Seq Scan on public.users u` | 7 | 0 | shared hit=794 read=449556, temp read=67700 written=67988 | 2,087.3 ms |
| Strategy A | `Parallel Hash Join, Parallel Seq Scan on public.orders o, Parallel Seq Scan on public.users u` | 7 | 0 | shared hit=1466 read=448884, temp read=67698 written=67992 | 1,112.3 ms |

**Strategy B — Rewrite the cross-table OR as UNION (each branch uses its own index)**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q3 rewritten with UNION | `Sort, Append, Nested Loop, Index Scan using uq_orders_order_number on public.orders o, Index Scan using pk_users on publ` | 7 | 0 | shared hit=22 | 0.027 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab14_users_phone;
-- (nothing to undo: query rewrite only)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `BitmapOr` = OR được phục vụ bởi nhiều index.
- `Join Filter` chứa OR giữa cột của hai bảng + `Rows Removed by Join Filter` khổng lồ.
- Seq Scan với `Filter: (a = ... OR b = ...)` → ít nhất một nhánh thiếu index.

## Interview Questions

1. PostgreSQL dùng nhiều index cho một điều kiện OR như thế nào?
2. Vì sao một nhánh OR thiếu index làm cả query phải Seq Scan?
3. Khi nào nên viết lại OR thành UNION / UNION ALL?
4. `a = 1 OR a = 2` có cần viết lại không? (gợi ý: `a IN (1, 2)` / `= ANY`)

## Key Takeaways

- OR chỉ dùng index khi **mọi** nhánh đều dùng được index.
- OR giữa cột của hai bảng chặn mọi index: viết lại thành UNION.
- UNION giữ đúng nghĩa OR (khử trùng lặp); UNION ALL nhanh hơn khi không cần.

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
