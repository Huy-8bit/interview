# Lab 20 · Large join: a 5-table revenue report

## Objective

Đọc và tối ưu một **join lớn 5 bảng**: theo dõi số dòng chảy qua từng node, nhận ra Memoize, và so sánh ba hướng: viết lại, thu hẹp bảng rộng, song song.

## Problem

Báo cáo doanh thu theo danh mục cấp 1 cho các đơn hoàn tất 6 tháng đầu 2026: orders → order_items (10M) → products (5M, 2 GB) → categories → categories.

## Baseline Query

Q1 — Revenue per top-level category, completed orders of H1 2026

```sql
SELECT parent.name        AS top_category,
       count(*)           AS order_lines,
       sum(i.total_price) AS revenue
FROM orders o
JOIN order_items i     ON i.order_id = o.id
JOIN products p        ON p.id = i.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
WHERE o.status = 'COMPLETED'
  AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
GROUP BY parent.name
ORDER BY revenue DESC;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Sort  (cost=297146.50..297146.62 rows=50 width=50) (actual time=3902.201..3923.460 rows=10 loops=1)
   Sort Key: (sum(i.total_price)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=1719353 read=651503
   ->  Finalize GroupAggregate  (cost=297131.79..297145.08 rows=50 width=50) (actual time=3902.077..3923.350 rows=10 loops=1)
         Group Key: parent.name
         Buffers: shared hit=1719353 read=651503
         ->  Gather Merge  (cost=297131.79..297143.46 rows=100 width=50) (actual time=3902.034..3923.304 rows=30 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=1719353 read=651503
               ->  Sort  (cost=296131.77..296131.89 rows=50 width=50) (actual time=3866.102..3866.115 rows=10 loops=3)
                     Sort Key: parent.name
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=1719353 read=651503
                     ->  Partial HashAggregate  (actual time=3865.879..3865.895 rows=10 loops=3)
                           Group Key: parent.name
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=1719337 read=651503
                           ->  Hash Join  (actual time=651.044..3769.175 rows=582849 loops=3)
                                 Inner Unique: true
                                 Hash Cond: (c.parent_id = parent.id)
                                 Buffers: shared hit=1719337 read=651503
                                 ->  Hash Join  (actual time=637.206..3699.137 rows=582849 loops=3)
                                       Inner Unique: true
                                       Hash Cond: (p.category_id = c.id)
                                       Buffers: shared hit=1719313 read=651502
                                       ->  Nested Loop  (actual time=637.179..3632.687 rows=582849 loops=3)
                                             Inner Unique: true
                                             Buffers: shared hit=1719310 read=651502
                                             ->  Parallel Hash Join  (actual time=636.933..1307.486 rows=582849 loops=3)
                                                   Inner Unique: true
                                                   Hash Cond: (i.order_id = o.id)
                                                   Buffers: shared hit=2579 read=137859
                                                   ->  Parallel Seq Scan on order_items i  (actual time=0.025..514.650 rows=3333715 loops=3)
                                                         Buffers: shared read=94358
                                                   ->  Parallel Hash  (actual time=269.537..269.545 rows=291376 loops=3)
                                                         Buckets: 1048576  Batches: 1  Memory Usage: 42432kB
                                                         Buffers: shared hit=2579 read=43501
                                                         ->  Parallel Index Scan using idx_orders_created_at on orders o  (actual time=0.229 ...
                                                               Index Cond: ((o.created_at >= '2026-01-01 00:00:00+00'::timestamp with time z ...
                                                               Filter: (o.status = 'COMPLETED'::order_status)
                                                               Rows Removed by Filter: 47930
                                                               Buffers: shared hit=2579 read=43501
                                             ->  Memoize  (cost=0.44..2.16 rows=1 width=12) (actual time=0.004..0.004 rows=1 loops=1748547)
                                                   Cache Key: i.product_id
                                                   Cache Mode: logical
                                                   Hits: 395927  Misses: 185823  Evictions: 41192  Overflows: 0  Memory Usage: 16385kB
                                                   Buffers: shared hit=1716731 read=513643
                                                   ->  Index Scan using pk_products on products p  (actual time=0.011..0.011 rows=1 loops=55 ...
                                                         Index Cond: (p.id = i.product_id)
                                                         Buffers: shared hit=1716731 read=513643
                                       ->  Hash  (cost=1.50..1.50 rows=50 width=8) (actual time=0.017..0.017 rows=50 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                             Buffers: shared hit=3
                                             ->  Seq Scan on categories c  (actual time=0.010..0.012 rows=50 loops=3)
                                                   Buffers: shared hit=3
                                 ->  Hash  (cost=1.50..1.50 rows=50 width=14) (actual time=13.816..13.817 rows=50 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 11kB
                                       Buffers: shared hit=2 read=1
                                       ->  Seq Scan on categories parent  (actual time=13.794..13.799 rows=50 loops=3)
                                             Buffers: shared hit=2 read=1
   Buffers: shared hit=13 read=25
 Planning Time: 4.063 ms
 Execution Time: 3925.850 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Đọc từ trong ra ngoài (rút gọn):

```text
Sort (revenue DESC)
  └── Finalize GroupAggregate ← Gather Merge ← Sort ← Partial HashAggregate (parent.name)
        └── Hash Join (parent)                         (5) gắn tên danh mục cha (50 dòng)
              └── Hash Join (c)                        (4) gắn danh mục con (50 dòng)
                    └── Nested Loop                    (3) mỗi dòng hàng → tra products
                          ├── Parallel Hash Join       (2) order_items ⋈ đơn hoàn tất của H1
                          │     ├── Parallel Seq Scan on order_items     (10M dòng)
                          │     └── Parallel Hash ← Parallel Index Scan on orders  (1) lọc đơn
                          └── Memoize (cache theo product_id)
                                └── Index Scan using pk_products         (~560k lookup thật)
```

~1.75 triệu dòng hàng đi lên node (3); Memoize trả ~70% từ cache (Hits), ~30% (Misses) phải tra
`pk_products` và đọc trang heap của bảng products rộng 2 GB.

## Bottleneck

Nested Loop + Memoize sang products: hàng trăm nghìn lần đọc ngẫu nhiên vào heap 2 GB chỉ để lấy `category_id`.

## Optimization Strategy A

**Rewrite: aggregate order lines per product BEFORE joining products** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Sort  (cost=292478.24..292478.36 rows=50 width=74) (actual time=3626.220..3628.811 rows=10 loops=1)
   Sort Key: (sum((sum(i.total_price)))) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=1300283 read=531064, temp read=14002 written=19672
   ->  GroupAggregate  (cost=292162.08..292476.83 rows=50 width=74) (actual time=3580.934..3628.804 rows=10 loops=1)
         Group Key: parent.name
         Buffers: shared hit=1300283 read=531064, temp read=14002 written=19672
         ->  Sort  (cost=292162.08..292240.58 rows=31400 width=50) (actual time=3578.826..3599.645 rows=422744 loops=1)
               Sort Key: parent.name
               Sort Method: external merge  Disk: 14928kB
               Buffers: shared hit=1300283 read=531064, temp read=14002 written=19672
               ->  Hash Join  (cost=221523.65..289816.73 rows=31400 width=50) (actual time=1280.618..3512.206 rows=422744 loops=1)
                     Inner Unique: true
                     Hash Cond: (c.parent_id = parent.id)
                     Buffers: shared hit=1300283 read=531064, temp read=12136 written=17803
                     ->  Hash Join  (cost=221521.52..289726.60 rows=31400 width=44) (actual time=1272.260..3464.605 rows=422744 loops=1)
                           Inner Unique: true
                           Hash Cond: (p.category_id = c.id)
                           Buffers: shared hit=1300283 read=531063, temp read=12136 written=17803
                           ->  Nested Loop  (actual time=1272.246..3421.738 rows=422744 loops=1)
                                 Inner Unique: true
                                 Buffers: shared hit=1300282 read=531063, temp read=12136 written=17803
                                 ->  Finalize HashAggregate  (actual time=1272.147..1515.918 rows=422744 loops=1)
                                       Group Key: i.product_id
                                       Batches: 21  Memory Usage: 16945kB  Disk Usage: 48672kB
                                       Buffers: shared hit=2510 read=137859, temp read=12136 written=17803
                                       ->  Gather  (actual time=1049.812..1137.068 rows=552600 loops=1)
                                             Workers Planned: 2
                                             Workers Launched: 2
                                             Buffers: shared hit=2510 read=137859, temp read=2504 written=4702
                                             ->  Partial HashAggregate  (actual time=1022.394..1105.162 rows=184200 loops=3)
                                                   Group Key: i.product_id
                                                   Batches: 5  Memory Usage: 16433kB  Disk Usage: 7632kB
                                                   Buffers: shared hit=2510 read=137859, temp read=2504 written=4702
                                                   ->  Parallel Hash Join  (actual time=347.150..899.081 rows=582849 loops=3)
                                                         Inner Unique: true
                                                         Hash Cond: (i.order_id = o.id)
                                                         Buffers: shared hit=2510 read=137859
                                                         ->  Parallel Seq Scan on order_items i  (actual time=0.046..250.148 rows=3333715 lo ...
                                                               Buffers: shared read=94358
                                                         ->  Parallel Hash  (actual time=197.386..197.387 rows=291376 loops=3)
                                                               Buckets: 1048576  Batches: 1  Memory Usage: 42432kB
                                                               Buffers: shared hit=2510 read=43501
                                                               ->  Parallel Index Scan using idx_orders_created_at on orders o  (actual time ...
                                                                     Index Cond: ((o.created_at >= '2026-01-01 00:00:00+00'::timestamp with  ...
                                                                     Filter: (o.status = 'COMPLETED'::order_status)
                                                                     Rows Removed by Filter: 47930
                                                                     Buffers: shared hit=2510 read=43501
                                 ->  Index Scan using pk_products on products p  (actual time=0.004..0.004 rows=1 loops=422744)
                                       Index Cond: (p.id = i.product_id)
                                       Buffers: shared hit=1297772 read=393204
                           ->  Hash  (cost=1.50..1.50 rows=50 width=8) (actual time=0.007..0.008 rows=50 loops=1)
                                 Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                 Buffers: shared hit=1
                                 ->  Seq Scan on categories c  (cost=0.00..1.50 rows=50 width=8) (actual time=0.003..0.004 rows=50 loops=1)
                                       Buffers: shared hit=1
                     ->  Hash  (cost=1.50..1.50 rows=50 width=14) (actual time=8.352..8.353 rows=50 loops=1)
                           Buckets: 1024  Batches: 1  Memory Usage: 11kB
                           Buffers: shared read=1
                           ->  Seq Scan on categories parent  (cost=0.00..1.50 rows=50 width=14) (actual time=8.341..8.343 rows=50 loops=1)
                                 Buffers: shared read=1
   Buffers: shared hit=6 read=16
 Planning Time: 0.626 ms
 Execution Time: 3634.878 ms
```

Thời gian giảm nhẹ; số dòng vào join products giảm (~423k thay vì ~1.75M) nhưng aggregate trước đó tràn đĩa.

## Why It Improved

Ba strategy, ba kết quả khác nhau (xem bảng):

- **A — gom nhóm trước khi join** (viết lại): chỉ cải thiện nhẹ. Bước `GROUP BY product_id` với hàng trăm
  nghìn nhóm bị tràn đĩa (`Batches: 21`) và phần sau của plan mất song song.
- **B — covering index `products (id) INCLUDE (category_id)`**: lookup thành Index Only Scan trên một
  cấu trúc nhỏ (~150 MB thay vì heap 2 GB) → nhanh hơn rõ rệt.
- **C — 4 parallel worker**: chia nhỏ công việc → nhanh nhất về thời gian thực, nhưng tổng công việc không đổi.

## Trade-offs

- Viết lại query không phải lúc nào cũng thắng; nó thay đổi plan theo những cách khó đoán (mất parallel, đổi loại aggregate).
- Covering index: thêm 150 MB và chi phí ghi trên products.
- Thêm worker: tốn CPU, giới hạn bởi `max_parallel_workers` và tải đồng thời của server.
- Báo cáo chạy thường xuyên → cân nhắc materialized view (Lab 41).

## Optimization Strategy B

**Narrow the wide table: covering index products (id) INCLUDE (category_id)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab20_products_id_category ON products (id) INCLUDE (category_id);
VACUUM (ANALYZE) products;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Sort  (cost=270553.61..270553.73 rows=50 width=50) (actual time=2232.233..2257.315 rows=10 loops=1)
   Sort Key: (sum(i.total_price)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=2112619 read=153597
   ->  Finalize GroupAggregate  (cost=270538.90..270552.20 rows=50 width=50) (actual time=2232.126..2257.223 rows=10 loops=1)
         Group Key: parent.name
         Buffers: shared hit=2112619 read=153597
         ->  Gather Merge  (cost=270538.90..270550.57 rows=100 width=50) (actual time=2231.943..2257.031 rows=30 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=2112619 read=153597
               ->  Sort  (cost=269538.88..269539.01 rows=50 width=50) (actual time=2130.618..2130.651 rows=10 loops=3)
                     Sort Key: parent.name
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=2112619 read=153597
                     ->  Partial HashAggregate  (actual time=2128.544..2128.577 rows=10 loops=3)
                           Group Key: parent.name
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=2112603 read=153597
                           ->  Hash Join  (actual time=536.959..2056.256 rows=582849 loops=3)
                                 Inner Unique: true
                                 Hash Cond: (c.parent_id = parent.id)
                                 Buffers: shared hit=2112603 read=153597
                                 ->  Hash Join  (actual time=517.129..1989.968 rows=582849 loops=3)
                                       Inner Unique: true
                                       Hash Cond: (p.category_id = c.id)
                                       Buffers: shared hit=2112579 read=153596
                                       ->  Nested Loop  (actual time=517.094..1939.127 rows=582849 loops=3)
                                             Inner Unique: true
                                             Buffers: shared hit=2112576 read=153596
                                             ->  Parallel Hash Join  (actual time=516.974..1246.808 rows=582849 loops=3)
                                                   Inner Unique: true
                                                   Hash Cond: (i.order_id = o.id)
                                                   Buffers: shared hit=2612 read=137859
                                                   ->  Parallel Seq Scan on order_items i  (actual time=0.046..428.923 rows=3333715 loops=3)
                                                         Buffers: shared read=94358
                                                   ->  Parallel Hash  (actual time=321.912..321.918 rows=291376 loops=3)
                                                         Buckets: 1048576  Batches: 1  Memory Usage: 42432kB
                                                         Buffers: shared hit=2612 read=43501
                                                         ->  Parallel Index Scan using idx_orders_created_at on orders o  (actual time=0.125 ...
                                                               Index Cond: ((o.created_at >= '2026-01-01 00:00:00+00'::timestamp with time z ...
                                                               Filter: (o.status = 'COMPLETED'::order_status)
                                                               Rows Removed by Filter: 47930
                                                               Buffers: shared hit=2612 read=43501
                                             ->  Memoize  (cost=0.44..1.31 rows=1 width=12) (actual time=0.001..0.001 rows=1 loops=1748547)
                                                   Cache Key: i.product_id
                                                   Cache Mode: logical
                                                   Hits: 396277  Misses: 185578  Evictions: 40947  Overflows: 0  Memory Usage: 16385kB
                                                   Buffers: shared hit=2109964 read=15737
                                                   ->  Index Only Scan using ix_lab20_products_id_category on products p  (actual time=0.002 ...
                                                         Index Cond: (p.id = i.product_id)
                                                         Heap Fetches: 0
                                                         Buffers: shared hit=2109964 read=15737
                                       ->  Hash  (cost=1.50..1.50 rows=50 width=8) (actual time=0.018..0.018 rows=50 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                             Buffers: shared hit=3
                                             ->  Seq Scan on categories c  (actual time=0.012..0.014 rows=50 loops=3)
                                                   Buffers: shared hit=3
                                 ->  Hash  (cost=1.50..1.50 rows=50 width=14) (actual time=19.803..19.803 rows=50 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 11kB
                                       Buffers: shared hit=2 read=1
                                       ->  Seq Scan on categories parent  (actual time=19.781..19.787 rows=50 loops=3)
                                             Buffers: shared hit=2 read=1
   Buffers: shared hit=16 read=22
 Planning Time: 4.252 ms
 Execution Time: 2260.870 ms
```

Lookup products thành `Index Only Scan using ix_lab20_products_id_category` (Heap Fetches 0) — nhanh hơn rõ rệt.

## Optimization Strategy C

**(experiment) more parallel workers: max_parallel_workers_per_gather = 4** — file [`02c_strategy_c.sql`](02c_strategy_c.sql)

## Result (Strategy C)

AFTER Strategy C — Q1:

```text
 Sort  (cost=265005.75..265005.87 rows=50 width=50) (actual time=1524.053..1534.482 rows=10 loops=1)
   Sort Key: (sum(i.total_price)) DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared hit=1934588 read=675451
   ->  Finalize GroupAggregate  (cost=264977.77..265004.34 rows=50 width=50) (actual time=1524.010..1534.467 rows=10 loops=1)
         Group Key: parent.name
         Buffers: shared hit=1934588 read=675451
         ->  Gather Merge  (cost=264977.77..265001.71 rows=200 width=50) (actual time=1523.977..1534.416 rows=50 loops=1)
               Workers Planned: 4
               Workers Launched: 4
               Buffers: shared hit=1934588 read=675451
               ->  Sort  (cost=263977.71..263977.83 rows=50 width=50) (actual time=1514.131..1514.135 rows=10 loops=5)
                     Sort Key: parent.name
                     Sort Method: quicksort  Memory: 26kB
                     Buffers: shared hit=1934588 read=675451
                     ->  Partial HashAggregate  (actual time=1514.104..1514.110 rows=10 loops=5)
                           Group Key: parent.name
                           Batches: 1  Memory Usage: 24kB
                           Buffers: shared hit=1934556 read=675451
                           ->  Hash Join  (actual time=166.954..1466.758 rows=349709 loops=5)
                                 Inner Unique: true
                                 Hash Cond: (c.parent_id = parent.id)
                                 Buffers: shared hit=1934556 read=675451
                                 ->  Hash Join  (actual time=158.195..1425.911 rows=349709 loops=5)
                                       Inner Unique: true
                                       Hash Cond: (p.category_id = c.id)
                                       Buffers: shared hit=1934508 read=675450
                                       ->  Nested Loop  (actual time=158.175..1391.039 rows=349709 loops=5)
                                             Inner Unique: true
                                             Buffers: shared hit=1934503 read=675450
                                             ->  Parallel Hash Join  (actual time=158.127..519.210 rows=349709 loops=5)
                                                   Inner Unique: true
                                                   Hash Cond: (i.order_id = o.id)
                                                   Buffers: shared hit=2642 read=137859
                                                   ->  Parallel Seq Scan on order_items i  (actual time=0.018..107.386 rows=2000229 loops=5)
                                                         Buffers: shared read=94358
                                                   ->  Parallel Hash  (actual time=79.340..79.340 rows=174825 loops=5)
                                                         Buckets: 1048576  Batches: 1  Memory Usage: 42464kB
                                                         Buffers: shared hit=2642 read=43501
                                                         ->  Parallel Index Scan using idx_orders_created_at on orders o  (actual time=0.040 ...
                                                               Index Cond: ((o.created_at >= '2026-01-01 00:00:00+00'::timestamp with time z ...
                                                               Filter: (o.status = 'COMPLETED'::order_status)
                                                               Rows Removed by Filter: 28758
                                                               Buffers: shared hit=2642 read=43501
                                             ->  Memoize  (cost=0.44..2.16 rows=1 width=12) (actual time=0.002..0.002 rows=1 loops=1748547)
                                                   Cache Key: i.product_id
                                                   Cache Mode: logical
                                                   Hits: 234339  Misses: 127240  Evictions: 0  Overflows: 0  Memory Usage: 14414kB
                                                   Buffers: shared hit=1931861 read=537591
                                                   ->  Index Scan using pk_products on products p  (actual time=0.006..0.006 rows=1 loops=61 ...
                                                         Index Cond: (p.id = i.product_id)
                                                         Buffers: shared hit=1931861 read=537591
                                       ->  Hash  (cost=1.50..1.50 rows=50 width=8) (actual time=0.010..0.011 rows=50 loops=5)
                                             Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                             Buffers: shared hit=5
                                             ->  Seq Scan on categories c  (actual time=0.005..0.007 rows=50 loops=5)
                                                   Buffers: shared hit=5
                                 ->  Hash  (cost=1.50..1.50 rows=50 width=14) (actual time=8.745..8.746 rows=50 loops=5)
                                       Buckets: 1024  Batches: 1  Memory Usage: 11kB
                                       Buffers: shared hit=4 read=1
                                       ->  Seq Scan on categories parent  (actual time=8.729..8.733 rows=50 loops=5)
                                             Buffers: shared hit=4 read=1
   Buffers: shared hit=13 read=25
 Planning Time: 0.412 ms
 Execution Time: 1535.409 ms
```

`Workers Launched: 4` — thời gian thực thấp nhất trong các phương án.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Revenue per top-level category, completed orders of H1 2026**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Finalize GroupAggregate, Sort, Partial HashAggregate, Hash Join, Nested Loop, Parallel Hash Join, Parallel Seq Scan on p` | 10 | 47,930 | shared hit=1719353 read=651503 | 3,925.8 ms |
| Strategy B | `Finalize GroupAggregate, Sort, Partial HashAggregate, Hash Join, Nested Loop, Parallel Hash Join, Parallel Seq Scan on p` | 10 | 47,930 | shared hit=2112619 read=153597 | 2,260.9 ms |

**Strategy A — Rewrite: aggregate order lines per product BEFORE joining products**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Pre-aggregated version | `GroupAggregate, Sort, Hash Join, Nested Loop, Finalize HashAggregate, Partial HashAggregate, Parallel Hash Join, Paralle` | 10 | 47,930 | shared hit=1300283 read=531064, temp read=14002 written=19672 | 3,634.9 ms |

**Strategy C — (experiment) more parallel workers: max_parallel_workers_per_gather = 4**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Baseline query with up to 4 workers | `Finalize GroupAggregate, Sort, Partial HashAggregate, Hash Join, Nested Loop, Parallel Hash Join, Parallel Seq Scan on p` | 10 | 28,758 | shared hit=1934588 read=675451 | 1,535.4 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
DROP INDEX IF EXISTS ix_lab20_products_id_category;
RESET max_parallel_workers_per_gather;
ANALYZE products;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Số dòng (`actual rows × loops`) đi qua từng node: chỗ dòng "phình ra" là chỗ cần chú ý.
- `Memoize`: Hits / Misses / Evictions; `Memory Usage` chạm giới hạn → Evictions.
- Buffers phân bố theo bảng: bảng rộng bị tra nhiều lần là ứng viên cho covering index.

## Interview Questions

1. Cách đọc một plan join nhiều bảng?
2. Memoize giúp gì cho Nested Loop?
3. Khi nào nên gom nhóm trước khi join?
4. Bảng rộng ảnh hưởng thế nào đến chi phí join?
5. Parallel query giảm thời gian hay giảm tổng công việc?

## Key Takeaways

- Theo dõi số dòng qua từng node để tìm điểm nghẽn.
- Bảng rộng làm mọi lookup đắt: covering index thu hẹp nó.
- Viết lại query là thí nghiệm — đo trước khi tin.
- Song song giảm thời gian thực, không giảm công việc.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`02b_strategy_b.sql`](02b_strategy_b.sql) | Strategy B |
| [`02c_strategy_c.sql`](02c_strategy_c.sql) | Strategy C |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
