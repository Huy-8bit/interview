# Lab 27 · Subquery vs JOIN: what the planner rewrites for you

## Objective

So sánh subquery và JOIN có cùng ý nghĩa nghiệp vụ; thấy planner tự viết lại những gì (semi join) và không viết lại những gì (scalar subquery tương quan).

## Problem

Q1: những khách đã mua sản phẩm bán chạy nhất. Q2: số đơn và đơn gần nhất của 20k khách, viết bằng hai scalar subquery tương quan.

## Baseline Query

Q1 — Customers who bought the best-selling product (IN subquery)

```sql
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id
               FROM orders o
               JOIN order_items i ON i.order_id = o.id
               WHERE i.product_id = 4905450);
```

Q2 — Order count and last order per customer (correlated scalar subqueries)

```sql
SELECT u.id, u.username,
       (SELECT count(*)          FROM orders o WHERE o.user_id = u.id) AS orders,
       (SELECT max(o.created_at) FROM orders o WHERE o.user_id = u.id) AS last_order
FROM users u
WHERE u.id BETWEEN 3000000 AND 3020000;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Aggregate  (cost=131352.73..131352.74 rows=1 width=8) (actual time=344.977..345.491 rows=1 loops=1)
   Buffers: shared hit=213516 read=85958
   ->  Nested Loop  (cost=78999.40..131251.89 rows=40338 width=0) (actual time=216.157..344.500 rows=34206 loops=1)
         Inner Unique: true
         Buffers: shared hit=213516 read=85958
         ->  HashAggregate  (cost=78998.97..79402.35 rows=40338 width=8) (actual time=216.130..222.066 rows=34206 loops=1)
               Group Key: o.user_id
               Batches: 1  Memory Usage: 3089kB
               Buffers: shared hit=93611 read=73319
               ->  Gather  (cost=1366.29..78898.12 rows=40338 width=8) (actual time=15.657..206.789 rows=34485 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=93611 read=73319
                     ->  Nested Loop  (cost=366.29..73864.32 rows=16808 width=8) (actual time=8.438..195.522 rows=11495 loops=3)
                           Inner Unique: true
                           Buffers: shared hit=93611 read=73319
                           ->  Parallel Bitmap Heap Scan on order_items i  (actual time=3.347..64.086 rows=11495 loops=3)
                                 Recheck Cond: (i.product_id = 4905450)
                                 Heap Blocks: exact=10513
                                 Buffers: shared read=28988
                                 ->  Bitmap Index Scan on idx_order_items_product_id  (actual time=5.455..5.455 rows=34485 loops=1)
                                       Index Cond: (i.product_id = 4905450)
                                       Buffers: shared read=32
                           ->  Index Scan using pk_orders on orders o  (actual time=0.011..0.011 rows=1 loops=34485)
                                 Index Cond: (o.id = i.order_id)
                                 Buffers: shared hit=93611 read=44331
         ->  Index Only Scan using pk_users on users u  (cost=0.43..1.29 rows=1 width=8) (actual time=0.003..0.003 rows=1 loops=34206)
               Index Cond: (u.id = o.user_id)
               Heap Fetches: 0
               Buffers: shared hit=119905 read=12639
   Buffers: shared hit=14 read=18
 Planning Time: 0.363 ms
 Execution Time: 345.847 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Q1 — `IN (subquery)` **không** chạy subquery cho từng user: planner đổi nó thành **semi join**.
```text
Aggregate
  └── Nested Loop
        ├── HashAggregate (distinct user_id)  ← Nested Loop(order_items → orders)   (người mua)
        └── Index Only Scan using pk_users                                            (tra user)
```
Q2 — scalar subquery trong SELECT list **không** được làm phẳng thành join:
```text
Index Scan using pk_users on users u          (20,001 users)
  SubPlan 1 → Aggregate ← Index Only Scan using idx_orders_user_id   loops=20001
  SubPlan 2 → Aggregate ← Index Scan using idx_orders_user_id        loops=20001
```

## Bottleneck

Q2: 2 × 20,001 lần tra index riêng lẻ (một lần cho mỗi user, mỗi subquery).

## Optimization Strategy A

**Q1 as JOIN + DISTINCT (the 'manual' rewrite)** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=102558.30..102558.31 rows=1 width=8) (actual time=198.775..204.561 rows=1 loops=1)
   Buffers: shared hit=210346 read=88066
   ->  Gather Merge  (cost=97759.43..102457.46 rows=40338 width=8) (actual time=195.846..203.632 rows=34485 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=210346 read=88066
         ->  Sort  (cost=96759.41..96801.43 rows=16808 width=8) (actual time=186.919..187.167 rows=11495 loops=3)
               Sort Key: u.id
               Sort Method: quicksort  Memory: 385kB
               Buffers: shared hit=210346 read=88066
               ->  Nested Loop  (cost=366.72..95579.75 rows=16808 width=8) (actual time=4.870..185.669 rows=11495 loops=3)
                     Inner Unique: true
                     Buffers: shared hit=210332 read=88064
                     ->  Nested Loop  (cost=366.29..73864.32 rows=16808 width=8) (actual time=4.848..141.576 rows=11495 loops=3)
                           Inner Unique: true
                           Buffers: shared hit=93611 read=73319
                           ->  Parallel Bitmap Heap Scan on order_items i  (actual time=2.024..44.288 rows=11495 loops=3)
                                 Recheck Cond: (i.product_id = 4905450)
                                 Heap Blocks: exact=10835
                                 Buffers: shared read=28988
                                 ->  Bitmap Index Scan on idx_order_items_product_id  (actual time=3.121..3.121 rows=34485 loops=1)
                                       Index Cond: (i.product_id = 4905450)
                                       Buffers: shared read=32
                           ->  Index Scan using pk_orders on orders o  (actual time=0.008..0.008 rows=1 loops=34485)
                                 Index Cond: (o.id = i.order_id)
                                 Buffers: shared hit=93611 read=44331
                     ->  Index Only Scan using pk_users on users u  (actual time=0.004..0.004 rows=1 loops=34485)
                           Index Cond: (u.id = o.user_id)
                           Heap Fetches: 0
                           Buffers: shared hit=116721 read=14745
   Buffers: shared hit=13 read=19
 Planning Time: 0.281 ms
 Execution Time: 204.846 ms
```

JOIN + DISTINCT: kết quả giống hệt, plan khác (song song + sort để khử trùng lặp).

## Why It Improved

Q2 viết lại thành **một** `LEFT JOIN (SELECT user_id, count(*), max(created_at) … GROUP BY user_id)`:
planner dùng `Merge Left Join` giữa `pk_users` và một `GroupAggregate` trên `idx_orders_user_id` — một
lần quét cho tất cả: nhanh hơn ~3 lần.

## Trade-offs

- Q1 viết "thủ công" thành JOIN + `count(DISTINCT)` phải khử trùng lặp. Trên lab nó cho một plan song
  song khác và thời gian *tương đương hoặc nhanh hơn* — nhưng đó là hệ quả của plan cụ thể, không phải quy
  luật "JOIN nhanh hơn subquery". Với IN/EXISTS, planner đã tự chọn semi join.
- LEFT JOIN giữ nguyên ngữ nghĩa với user không có đơn (count = 0 qua `coalesce`, last_order NULL);
  INNER JOIN sẽ làm mất họ.

## Optimization Strategy B

**Q2: one grouped LEFT JOIN instead of two correlated subqueries** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=131352.73..131352.74 rows=1 width=8) (actual time=253.901..254.487 rows=1 loops=1)
   Buffers: shared hit=213519 read=85958
   ->  Nested Loop  (cost=78999.40..131251.89 rows=40338 width=0) (actual time=161.973..253.606 rows=34206 loops=1)
         Inner Unique: true
         Buffers: shared hit=213519 read=85958
         ->  HashAggregate  (cost=78998.97..79402.35 rows=40338 width=8) (actual time=161.938..166.261 rows=34206 loops=1)
               Group Key: o.user_id
               Batches: 1  Memory Usage: 3089kB
               Buffers: shared hit=93611 read=73319
               ->  Gather  (cost=1366.29..78898.12 rows=40338 width=8) (actual time=10.700..155.186 rows=34485 loops=1)
                     Workers Planned: 2
                     Workers Launched: 2
                     Buffers: shared hit=93611 read=73319
                     ->  Nested Loop  (cost=366.29..73864.32 rows=16808 width=8) (actual time=5.499..149.621 rows=11495 loops=3)
                           Inner Unique: true
                           Buffers: shared hit=93611 read=73319
                           ->  Parallel Bitmap Heap Scan on order_items i  (actual time=2.096..47.287 rows=11495 loops=3)
                                 Recheck Cond: (i.product_id = 4905450)
                                 Heap Blocks: exact=9834
                                 Buffers: shared read=28988
                                 ->  Bitmap Index Scan on idx_order_items_product_id  (actual time=3.176..3.176 rows=34485 loops=1)
                                       Index Cond: (i.product_id = 4905450)
                                       Buffers: shared read=32
                           ->  Index Scan using pk_orders on orders o  (actual time=0.008..0.008 rows=1 loops=34485)
                                 Index Cond: (o.id = i.order_id)
                                 Buffers: shared hit=93611 read=44331
         ->  Index Only Scan using pk_users on users u  (cost=0.43..1.29 rows=1 width=8) (actual time=0.002..0.002 rows=1 loops=34206)
               Index Cond: (u.id = o.user_id)
               Heap Fetches: 0
               Buffers: shared hit=119908 read=12639
   Buffers: shared hit=14 read=18
 Planning Time: 0.379 ms
 Execution Time: 254.905 ms
```

Q2: `Merge Left Join` + `GroupAggregate`, không còn SubPlan loops=20001.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Customers who bought the best-selling product (IN subquery)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Nested Loop, HashAggregate, Parallel Bitmap Heap Scan on public.order_items i, Bitmap Index Scan on idx_order_items_prod` | 1 | 0 | shared hit=213516 read=85958 | 345.8 ms |
| Strategy B | `Nested Loop, HashAggregate, Parallel Bitmap Heap Scan on public.order_items i, Bitmap Index Scan on idx_order_items_prod` | 1 | 0 | shared hit=213519 read=85958 | 254.9 ms |

**Q2 — Order count and last order per customer (correlated scalar subqueries)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Aggregate, Index Only Scan using idx_orders_user_id on public.orders o, Index Scan using idx_orders_user_id on public.or` | 20001 | 0 | shared hit=155493 read=135 | 55.5 ms |
| Strategy B | `Index Scan using pk_users on public.users u, GroupAggregate, Index Scan using idx_orders_user_id on public.orders` | 20001 | 0 | shared hit=21162 read=131 | 18.7 ms |

**Strategy A — Q1 as JOIN + DISTINCT (the 'manual' rewrite)**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q1 as JOIN + DISTINCT | `Sort, Nested Loop, Parallel Bitmap Heap Scan on public.order_items i, Bitmap Index Scan on idx_order_items_product_id, I` | 1 | 0 | shared hit=210346 read=88066 | 204.8 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
-- (nothing to undo: query rewrite only)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Semi Join` / `Anti Join` trong plan = subquery IN/EXISTS đã được chuyển thành join.
- `SubPlan N` với `loops=` lớn = subquery chạy lại cho từng dòng.

## Interview Questions

1. PostgreSQL có tự chuyển IN (subquery) thành join không?
2. Semi join khác inner join + DISTINCT thế nào?
3. Scalar subquery tương quan trong SELECT list được thực thi ra sao? Viết lại thế nào?
4. Có phải 'JOIN luôn nhanh hơn subquery'?

## Key Takeaways

- IN / EXISTS → semi join: planner đã tối ưu, không cần viết lại.
- Scalar subquery tương quan chạy một lần mỗi dòng: thay bằng join với dữ liệu đã gom nhóm.
- Không có quy luật chung 'JOIN nhanh hơn' — so sánh plan.

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
