# Lab 25 · Window functions: the sort behind PARTITION BY ... ORDER BY

## Objective

Hiểu chi phí sort đằng sau window function (`PARTITION BY … ORDER BY`), Incremental Sort, Run Condition, và so với `DISTINCT ON`.

## Problem

'Đơn mới nhất của mỗi khách' cho 200k khách đầu tiên (`row_number() … WHERE rn = 1`), và xếp hạng giá trong một danh mục.

## Baseline Query

Q1 — Latest order of each customer (users 1..200,000) with row_number()

```sql
SELECT id, user_id, status, total_amount, created_at
FROM (
  SELECT o.id, o.user_id, o.status, o.total_amount, o.created_at,
         row_number() OVER (PARTITION BY o.user_id ORDER BY o.created_at DESC) AS rn
  FROM orders o
  WHERE o.user_id BETWEEN 1 AND 200000
) s
WHERE rn = 1;
```

Q2 — Price rank inside one category (281k products)

```sql
SELECT id, name, price, rank() OVER (ORDER BY price DESC) AS price_rank
FROM products
WHERE category_id = 37
ORDER BY price_rank
LIMIT 10;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Subquery Scan on s  (cost=1.09..142360.03 rows=1029 width=34) (actual time=3.191..535.362 rows=88593 loops=1)
   Filter: (s.rn = 1)
   Buffers: shared hit=51802 read=148468
   ->  WindowAgg  (cost=1.09..139787.81 rows=205778 width=42) (actual time=3.189..531.656 rows=88593 loops=1)
         Run Condition: (row_number() OVER (?) <= 1)
         Buffers: shared hit=51802 read=148468
         ->  Incremental Sort  (cost=1.09..136186.69 rows=205778 width=34) (actual time=3.183..507.617 rows=199883 loops=1)
               Sort Key: o.user_id, o.created_at DESC
               Presorted Key: o.user_id
               Full-sort Groups: 6003  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
               Buffers: shared hit=51802 read=148468
               ->  Index Scan using idx_orders_user_id on orders o  (actual time=3.096..489.334 rows=199883 loops=1)
                     Index Cond: ((o.user_id >= 1) AND (o.user_id <= 200000))
                     Buffers: shared hit=51802 read=148468
   Buffers: shared read=4
 Planning Time: 0.118 ms
 Execution Time: 537.072 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Subquery Scan (rn = 1)
  └── WindowAgg   Run Condition: (row_number() OVER (?) <= 1)
        └── Incremental Sort   Sort Key: user_id, created_at DESC   Presorted Key: user_id
              └── Index Scan using idx_orders_user_id    (đã sắp theo user_id)
```
WindowAgg cần dòng theo thứ tự `(user_id, created_at DESC)`. Index đã cho thứ tự theo `user_id`,
nên **Incremental Sort** chỉ phải sort từng nhóm nhỏ của một user (vài dòng) — gần như miễn phí.
`Run Condition` (PG15+) dừng tính row_number trong partition khi đã vượt 1.

## Bottleneck

Phần lớn thời gian là Index Scan đọc ~200k đơn rải rác trong heap; sort không phải nút thắt (nhờ Incremental Sort).

## Optimization Strategy A

**Index (user_id, created_at DESC): the window's order comes from the index** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab25_orders_user_created ON orders (user_id, created_at DESC);
ANALYZE orders;
```

## Result

AFTER Strategy A — Q1:

```text
 Subquery Scan on s  (cost=1.10..137948.43 rows=994 width=34) (actual time=3.343..507.397 rows=88593 loops=1)
   Filter: (s.rn = 1)
   Buffers: shared hit=51775 read=148495
   ->  WindowAgg  (cost=1.10..135464.26 rows=198733 width=42) (actual time=3.341..503.739 rows=88593 loops=1)
         Run Condition: (row_number() OVER (?) <= 1)
         Buffers: shared hit=51775 read=148495
         ->  Incremental Sort  (cost=1.10..131986.44 rows=198733 width=34) (actual time=3.333..481.170 rows=199883 loops=1)
               Sort Key: o.user_id, o.created_at DESC
               Presorted Key: o.user_id
               Full-sort Groups: 6003  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
               Buffers: shared hit=51775 read=148495
               ->  Index Scan using idx_orders_user_id on orders o  (actual time=3.227..463.315 rows=199883 loops=1)
                     Index Cond: ((o.user_id >= 1) AND (o.user_id <= 200000))
                     Buffers: shared hit=51775 read=148495
   Buffers: shared read=4
 Planning Time: 0.219 ms
 Execution Time: 509.118 ms
```

Plan không đổi (`Incremental Sort` trên `idx_orders_user_id`).

## Why It Improved

Strategy A tạo `(user_id, created_at DESC)` nhưng planner **vẫn giữ plan cũ**: Incremental Sort trên
`idx_orders_user_id` đã rẻ, index mới không đem lại lợi ích về cost (vẫn phải đọc heap cho các cột khác).
Một index "đúng sách" không có giá trị nếu plan hiện tại đã gần tối ưu.

## Trade-offs

- Index thêm ~190 MB mà không được dùng: chi phí thuần — phải drop.
- Q2 (rank trong 281k sản phẩm): Sort toàn bộ danh mục là không tránh được vì rank cần thứ tự giá trên
  tất cả dòng; chỉ một index `(category_id, price DESC)` mới loại bỏ được sort (xem Lab 05).

## Optimization Strategy B

**Rewrite with DISTINCT ON (user_id)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Unique  (cost=1.09..137154.26 rows=197762 width=34) (actual time=5.240..536.227 rows=88593 loops=1)
   Buffers: shared hit=51780 read=148490
   ->  Incremental Sort  (cost=1.09..136632.11 rows=208859 width=34) (actual time=5.239..528.565 rows=199883 loops=1)
         Sort Key: o.user_id, o.created_at DESC
         Presorted Key: o.user_id
         Full-sort Groups: 6003  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
         Buffers: shared hit=51780 read=148490
         ->  Index Scan using idx_orders_user_id on orders o  (actual time=4.971..501.695 rows=199883 loops=1)
               Index Cond: ((o.user_id >= 1) AND (o.user_id <= 200000))
               Buffers: shared hit=51780 read=148490
   Buffers: shared read=4
 Planning Time: 0.294 ms
 Execution Time: 538.172 ms
```

`DISTINCT ON (user_id) … ORDER BY user_id, created_at DESC`: `Unique` trên cùng Incremental Sort — cùng chi phí, query đơn giản hơn.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Latest order of each customer (users 1..200,000) with row_number()**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Incremental Sort, Index Scan using idx_orders_user_id on public.orders o` | 88593 | 0 | shared hit=51802 read=148468 | 537.1 ms |
| Strategy A | `Incremental Sort, Index Scan using idx_orders_user_id on public.orders o` | 88593 | 0 | shared hit=51775 read=148495 | 509.1 ms |

**Q2 — Price rank inside one category (281k products)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Index Scan using idx_products_category_id on public.products` | 10 | 0 | shared read=174724, temp read=1913 written=1916 | 577.2 ms |
| Strategy A | `Sort, Index Scan using idx_products_category_id on public.products` | 10 | 0 | shared read=174724, temp read=1913 written=1916 | 736.4 ms |

**Strategy B — Rewrite with DISTINCT ON (user_id)**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Latest order per customer with DISTINCT ON | `Incremental Sort, Index Scan using idx_orders_user_id on public.orders o` | 88593 | 0 | shared hit=51780 read=148490 | 538.2 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab25_orders_user_created;
-- (nothing to undo: query rewrite only)
ANALYZE orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `WindowAgg` và node bên dưới: Sort / Incremental Sort (Presorted Key) / không sort.
- `Run Condition` trên WindowAgg.
- `Full-sort Groups`, `Average Memory` của Incremental Sort.

## Interview Questions

1. Window function cần đầu vào sắp xếp thế nào?
2. Incremental Sort là gì? Khi nào planner dùng nó?
3. row_number() = 1 vs DISTINCT ON vs LATERAL … LIMIT 1 — chọn cái nào khi nào?
4. Run Condition giúp gì?

## Key Takeaways

- Chi phí của window function chủ yếu là sort theo PARTITION BY + ORDER BY.
- Incremental Sort tận dụng thứ tự có sẵn một phần — thường đủ tốt mà không cần index mới.
- Đừng tạo index khi plan không dùng nó.

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
