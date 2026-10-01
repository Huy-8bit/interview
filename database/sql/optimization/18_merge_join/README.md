# Lab 18 · Merge Join: two inputs already sorted on the join key

## Objective

Hiểu **Merge Join**: hai đầu vào đã sắp theo khóa join được trộn song song; khi nào planner tự chọn nó và cái giá của Sort khi thiếu thứ tự sẵn.

## Problem

Xuất toàn bộ đơn hàng kèm thanh toán theo thứ tự id (đối soát / export) và 100k dòng hàng đầu tiên theo thứ tự đơn.

## Baseline Query

Q1 — Every order with its payments, in order id order (5M+ rows - not fetched to the client)

```sql
SELECT o.id, o.status, p.status AS payment_status, p.amount
FROM orders o
JOIN payments p ON p.order_id = o.id
ORDER BY o.id;
```

Q2 — First 100,000 order lines in order id order

```sql
SELECT o.id, o.created_at, i.product_id, i.quantity
FROM orders o
JOIN order_items i ON i.order_id = o.id
ORDER BY o.id
LIMIT 100000;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Merge Join  (cost=51.22..560910.62 rows=5128816 width=22) (actual time=38.352..2778.722 rows=5128816 loops=1)
   Merge Cond: (o.id = p.order_id)
   Buffers: shared hit=6001 read=329464
   ->  Index Scan using pk_orders on orders o  (actual time=0.013..1366.411 rows=5000000 loops=1)
         Buffers: shared hit=151 read=213657
   ->  Index Scan using idx_payments_order_id on payments p  (actual time=0.075..897.050 rows=5128816 loops=1)
         Buffers: shared hit=5850 read=115807
   Buffers: shared hit=4 read=12
 Planning Time: 0.806 ms
 Execution Time: 2859.961 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Merge Join   Merge Cond: (o.id = p.order_id)
  ├── Index Scan using pk_orders on orders o           (sorted by id)
  └── Index Scan using idx_payments_order_id on payments p   (sorted by order_id)
```

```text
sorted input A ──┐
                 ├─► advance the side with the smaller key, emit when keys are equal
sorted input B ──┘
```
Cả hai index đã cho thứ tự sẵn: không có Sort, và **đầu ra cũng đã sắp theo o.id** nên `ORDER BY o.id`
miễn phí. Dưới `LIMIT`, Merge Join dừng ngay khi đủ dòng (startup ≈ 0).

## Bottleneck

Q1 trả 5.1 triệu dòng: Merge Join chạy **một luồng** đọc qua hai index (~2.9 s trên lab). Không có
bottleneck rõ ràng khác — nhưng xem Strategy A.

## Optimization Strategy A

**(experiment) SET enable_mergejoin = off** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Gather Merge  (cost=672475.85..1171145.63 rows=4274014 width=22) (actual time=1313.038..1707.661 rows=5128816 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   Buffers: shared hit=28969 read=273045, temp read=67334 written=67653
   ->  Sort  (cost=671475.82..676818.34 rows=2137007 width=22) (actual time=1300.175..1390.599 rows=1709605 loops=3)
         Sort Key: o.id
         Sort Method: external merge  Disk: 54184kB
         Buffers: shared hit=28969 read=273045, temp read=67334 written=67653
         ->  Parallel Hash Join  (cost=257084.07..421129.78 rows=2137007 width=22) (actual time=861.447..1146.992 rows=1709605 loops=3)
               Inner Unique: true
               Hash Cond: (p.order_id = o.id)
               Buffers: shared hit=28895 read=273045, temp read=46614 written=46888
               ->  Parallel Seq Scan on payments p  (actual time=0.063..197.387 rows=1709605 loops=3)
                     Buffers: shared hit=8803 read=93045
               ->  Parallel Hash  (cost=220866.70..220866.70 rows=2083470 width=12) (actual time=494.516..494.516 rows=1666667 loops=3)
                     Buckets: 524288  Batches: 32  Memory Usage: 11488kB
                     Buffers: shared hit=20032 read=180000, temp written=19132
                     ->  Parallel Seq Scan on orders o  (actual time=42.313..329.817 rows=1666667 loops=3)
                           Buffers: shared hit=20032 read=180000
 Planning Time: 0.124 ms
 Execution Time: 1797.586 ms
```

Không có Merge Join: `Parallel Hash Join` + `Sort (external merge)` + `Gather Merge` — trên lab lại nhanh hơn nhờ song song.

## Why It Improved

Thí nghiệm Strategy A (tắt Merge Join) cho kết quả đáng suy ngẫm: Parallel Hash Join + Sort (external
merge ~55MB/worker) + Gather Merge lại **nhanh hơn** (~1.8 s) vì dùng 3 process. Planner ước lượng Merge
Join rẻ hơn, thực tế song song thắng. Mô hình chi phí không hoàn hảo — luôn đo.

## Trade-offs

- Merge Join cần đầu vào có thứ tự: từ index (rẻ) hoặc từ Sort (đắt với dữ liệu lớn — Strategy B).
- Hỗ trợ điều kiện `=` (và là loại join hỗ trợ FULL JOIN trên điều kiện merge được).
- Ưu điểm lớn: không cần bộ nhớ cho bảng băm, đầu ra có thứ tự, startup thấp.

## Optimization Strategy B

**(experiment) Merge join on an UNINDEXED key needs an explicit Sort** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize Aggregate  (cost=461607.92..461607.94 rows=1 width=40) (actual time=709.629..709.660 rows=1 loops=1)
   Buffers: shared hit=23973 read=104968, temp read=13135 written=13815
   ->  Gather  (cost=461607.70..461607.91 rows=2 width=40) (actual time=709.608..709.640 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=23973 read=104968, temp read=13135 written=13815
         ->  Partial Aggregate  (cost=460607.70..460607.71 rows=1 width=40) (actual time=692.246..692.246 rows=1 loops=3)
               Buffers: shared hit=23973 read=104968, temp read=13135 written=13815
               ->  Merge Join  (cost=365499.80..450191.04 rows=2083333 width=2) (actual time=371.873..659.563 rows=1249493 loops=3)
                     Inner Unique: true
                     Merge Cond: (r.order_id = o.id)
                     Buffers: shared hit=23973 read=104968, temp read=13135 written=13815
                     ->  Sort  (cost=365498.59..370706.93 rows=2083333 width=10) (actual time=370.238..416.498 rows=1249494 loops=3)
                           Sort Key: r.order_id
                           Sort Method: external merge  Disk: 38400kB
                           Buffers: shared hit=202 read=104968, temp read=13135 written=13815
                           ->  Parallel Seq Scan on reviews r  (actual time=3.788..155.162 rows=1666667 loops=3)
                                 Buffers: shared hit=192 read=104968
                     ->  Index Only Scan using pk_orders on orders o  (actual time=0.045..97.309 rows=2896106 loops=3)
                           Heap Fetches: 0
                           Buffers: shared hit=23771
   Buffers: shared hit=4
 Planning Time: 0.329 ms
 Execution Time: 712.807 ms
```

`reviews.order_id` không có index: ép Merge Join (tắt Hash Join) khiến planner phải **Sort 5 triệu review**
theo order_id (external merge ~37MB/worker) trước khi trộn với `pk_orders`.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Every order with its payments, in order id order (5M+ rows - not fetched to the client)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using pk_orders on public.orders o, Index Scan using idx_payments_order_id on public.payments p` | 5128816 | 0 | shared hit=6001 read=329464 | 2,860.0 ms |

**Q2 — First 100,000 order lines in order id order**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Merge Join, Index Scan using pk_orders on public.orders o, Index Scan using idx_order_items_order_id on public.order_ite` | 100000 | 0 | shared hit=3305 | 23.1 ms |

**Strategy A — (experiment) SET enable_mergejoin = off**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q1 with merge joins disabled | `Sort, Parallel Hash Join, Parallel Seq Scan on public.payments p, Parallel Seq Scan on public.orders o` | 5128816 | 0 | shared hit=28969 read=273045, temp read=67334 written=67653 | 1,797.6 ms |

**Strategy B — (experiment) Merge join on an UNINDEXED key needs an explicit Sort**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Orders joined with their reviews, hash join disabled | `Partial Aggregate, Merge Join, Sort, Parallel Seq Scan on public.reviews r, Index Only Scan using pk_orders on public.or` | 1 | 0 | shared hit=23973 read=104968, temp read=13135 written=13815 | 712.8 ms |

## Reset

```sql
RESET enable_mergejoin;
RESET enable_hashjoin;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Merge Join` + `Merge Cond`; hai con là Index Scan (có thứ tự sẵn) hay Sort.
- `Sort Method: external merge  Disk:` dưới Merge Join = cái giá của việc tạo thứ tự.
- Không có node Sort phía trên dù có ORDER BY: thứ tự đến từ Merge Join.

## Interview Questions

1. Merge Join cần điều kiện gì về đầu vào?
2. Khi nào Merge Join tốt hơn Hash Join?
3. Vì sao Merge Join hợp với LIMIT và ORDER BY theo khóa join?
4. Planner chọn Merge Join nhưng plan khác lại nhanh hơn — có thể vì sao?

## Key Takeaways

- Merge Join tỏa sáng khi cả hai phía đã có thứ tự từ index và kết quả cần thứ tự đó.
- Thiếu thứ tự → phải Sort → thường thua Hash Join.
- Song song (parallel) có thể thắng một plan 'rẻ hơn' trên giấy.

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
