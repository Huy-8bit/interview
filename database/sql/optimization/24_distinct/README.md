# Lab 24 · DISTINCT: full scan vs emulated skip scan, count(DISTINCT)

## Objective

Tối ưu `DISTINCT`: mô phỏng **skip scan** bằng recursive CTE, và hiểu cách `count(DISTINCT)` được thực thi.

## Problem

Liệt kê các danh mục đang có sản phẩm (40 giá trị trong 5 triệu dòng) và đếm số khách đã đặt hàng từ đầu tháng 9.

## Baseline Query

Q1 — Which categories have products? (40 values among 5M rows)

```sql
SELECT DISTINCT category_id
FROM products;
```

Q2 — How many distinct customers ordered since September?

```sql
SELECT count(DISTINCT user_id)
FROM orders
WHERE created_at >= '2026-09-01';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Unique  (cost=1000.46..56697.73 rows=40 width=4) (actual time=119.328..120.584 rows=40 loops=1)
   Buffers: shared hit=4895
   ->  Gather Merge  (cost=1000.46..56697.53 rows=80 width=4) (actual time=119.328..120.580 rows=81 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=4895
         ->  Unique  (cost=0.43..55688.27 rows=40 width=4) (actual time=0.010..78.683 rows=27 loops=3)
               Buffers: shared hit=4895
               ->  Parallel Index Only Scan using idx_products_category_id on products  (actual time=0.009..46.393 rows=1666667 loops=3)
                     Heap Fetches: 0
                     Buffers: shared hit=4895
 Planning Time: 0.051 ms
 Execution Time: 120.593 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Q1:
```text
Unique
  └── Gather Merge
        └── Unique
              └── Parallel Index Only Scan using idx_products_category_id   <- đọc 5M entry
```
PostgreSQL 16 không có *skip scan* (PG18 mới có): để lấy 40 giá trị phân biệt nó đọc mọi entry.

Q2: `count(DISTINCT user_id)` được tính bởi một Aggregate **tự sort đầu vào bên trong** (Sort node
hiện trong plan với `external merge`), không chạy song song được.

## Bottleneck

Q1 đọc ~5 triệu entry index cho 40 dòng. Q2 sort 1.66 triệu dòng ra đĩa.

## Optimization Strategy A

**Rewrite Q1 as a recursive 'skip scan' (loose index scan emulation)** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 CTE Scan on c  (cost=48.55..50.57 rows=100 width=4) (actual time=0.003..0.128 rows=40 loops=1)
   Filter: (c.category_id IS NOT NULL)
   Rows Removed by Filter: 1
   Buffers: shared hit=127
   CTE c
     ->  Recursive Union  (cost=0.43..48.55 rows=101 width=4) (actual time=0.003..0.123 rows=41 loops=1)
           Buffers: shared hit=127
           ->  Limit  (cost=0.43..0.45 rows=1 width=4) (actual time=0.003..0.003 rows=1 loops=1)
                 Buffers: shared hit=4
                 ->  Index Only Scan using idx_products_category_id on products  (actual time=0.003..0.003 rows=1 loops=1)
                       Heap Fetches: 0
                       Buffers: shared hit=4
           ->  WorkTable Scan on c c_1  (cost=0.00..4.71 rows=10 width=4) (actual time=0.003..0.003 rows=1 loops=41)
                 Filter: (c_1.category_id IS NOT NULL)
                 Rows Removed by Filter: 0
                 Buffers: shared hit=123
                 SubPlan 1
                   ->  Limit  (cost=0.43..0.45 rows=1 width=4) (actual time=0.003..0.003 rows=1 loops=40)
                         Buffers: shared hit=123
                         ->  Index Only Scan using idx_products_category_id on products p  (actual time=0.002..0.002 rows=1 loops=40)
                               Index Cond: (p.category_id > c_1.category_id)
                               Heap Fetches: 0
                               Buffers: shared hit=123
 Planning Time: 0.025 ms
 Execution Time: 0.134 ms
```

`Recursive Union` + SubPlan `Limit` → `Index Only Scan` với `loops=40`: micro giây.

## Why It Improved

Strategy A — recursive CTE: "lấy giá trị nhỏ nhất", rồi lặp "giá trị nhỏ nhất lớn hơn giá trị trước"
với `LIMIT 1` — mỗi bước là **một lần đi xuống B-tree**. 41 lần × vài trang thay vì 5 triệu entry:
từ ~120 ms xuống dưới 0.1 ms.

## Trade-offs

- Skip scan chỉ thắng khi số giá trị phân biệt **ít** so với số dòng. Với 2 triệu giá trị phân biệt,
  2 triệu lần đi xuống B-tree sẽ chậm hơn một lần quét.
- Query khó đọc hơn — đóng gói trong view hoặc comment rõ.
- Strategy B (Q2) là bài học ngược: viết lại thành `count(*) FROM (SELECT DISTINCT …)` cho HashAggregate
  **tràn đĩa 41 batch** và trên lab **chậm hơn** bản gốc. "Viết lại để planner tự chọn" không đảm bảo
  planner chọn tốt hơn.

## Optimization Strategy B

**Rewrite Q2: count(*) over SELECT DISTINCT** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=192859.52..192859.53 rows=1 width=8) (actual time=796.558..796.559 rows=1 loops=1)
   Buffers: shared hit=43 read=71032, temp read=6550 written=11830
   ->  HashAggregate  (cost=155503.40..179473.51 rows=1070881 width=8) (actual time=569.739..774.386 rows=1110052 loops=1)
         Group Key: orders.user_id
         Planned Partitions: 8  Batches: 41  Memory Usage: 20561kB  Disk Usage: 48184kB
         Buffers: shared hit=43 read=71032, temp read=6550 written=11830
         ->  Index Scan using idx_orders_created_at on orders  (actual time=0.025..247.525 rows=1662233 loops=1)
               Index Cond: (orders.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone)
               Buffers: shared hit=43 read=71032
 Planning Time: 0.073 ms
 Execution Time: 800.650 ms
```

HashAggregate (Batches 41, Disk Usage ~48MB) thay cho sort trong aggregate — chậm hơn bản gốc trên lab.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Which categories have products? (40 values among 5M rows)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Index Only Scan using idx_products_category_id on public.products` | 40 | 0 | shared hit=4895 | 120.6 ms |

**Q2 — How many distinct customers ordered since September?**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Index Scan using idx_orders_created_at on public.orders` | 1 | 0 | shared hit=43 read=71032, temp read=2444 written=2448 | 529.2 ms |

**Strategy A — Rewrite Q1 as a recursive 'skip scan' (loose index scan emulation)**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q1 as a recursive skip scan | `Index Only Scan using idx_products_category_id on public.products, WorkTable Scan on c c_1, Index Only Scan using idx_pr` | 40 | 1 | shared hit=127 | 0.134 ms |

**Strategy B — Rewrite Q2: count(*) over SELECT DISTINCT**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q2 rewritten | `HashAggregate, Index Scan using idx_orders_created_at on public.orders` | 1 | 0 | shared hit=43 read=71032, temp read=6550 written=11830 | 800.6 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
-- (nothing to undo: query rewrite only)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Unique` trên một scan đọc hàng triệu dòng để trả vài dòng → ứng viên skip scan.
- `loops=` của SubPlan trong recursive CTE = số giá trị phân biệt.
- `count(DISTINCT)`: Sort (thường external) trong Aggregate.

## Interview Questions

1. Skip scan / loose index scan là gì? PostgreSQL 16 có không?
2. Khi nào recursive CTE skip scan nhanh hơn DISTINCT?
3. count(DISTINCT x) được thực thi thế nào? Có song song được không?

## Key Takeaways

- Ít giá trị phân biệt + có index → mô phỏng skip scan bằng recursive CTE.
- Đừng giả định một cách viết lại 'chắc chắn nhanh hơn' — đo trên dữ liệu thật.

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
