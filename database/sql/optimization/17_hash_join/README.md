# Lab 17 · Hash Join: build the small side, probe with the big side

## Objective

Hiểu **Hash Join**: build bảng băm từ phía nhỏ, probe bằng phía lớn; đọc `Buckets`, `Batches`, `Memory Usage`.

## Problem

Báo cáo thanh toán của các đơn tháng 9/2026 (~1.66 triệu đơn) theo phương thức và trạng thái — join `payments` (5.1M) với `orders`.

## Baseline Query

Q1 — Payments of September's orders, by method and order status

```sql
SELECT p.payment_method, o.status, count(*) AS payments, sum(p.amount) AS amount
FROM payments p
JOIN orders o ON o.id = p.order_id
WHERE o.created_at >= '2026-09-01'
GROUP BY p.payment_method, o.status
ORDER BY p.payment_method, o.status;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize GroupAggregate  (cost=270505.95..270515.70 rows=36 width=48) (actual time=751.624..771.382 rows=36 loops=1)
   Group Key: p.payment_method, o.status
   Buffers: shared hit=4308 read=172886, temp read=33985 written=34040
   ->  Gather Merge  (cost=270505.95..270514.35 rows=72 width=48) (actual time=751.607..771.345 rows=108 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=4308 read=172886, temp read=33985 written=34040
         ->  Sort  (cost=269505.93..269506.02 rows=36 width=48) (actual time=740.555..740.735 rows=36 loops=3)
               Sort Key: p.payment_method, o.status
               Sort Method: quicksort  Memory: 28kB
               Buffers: shared hit=4308 read=172886, temp read=33985 written=34040
               ->  Partial HashAggregate  (cost=269504.55..269505.00 rows=36 width=48) (actual time=740.529..740.712 rows=36 loops=3)
                     Group Key: p.payment_method, o.status
                     Batches: 1  Memory Usage: 32kB
                     Buffers: shared hit=4292 read=172886, temp read=33985 written=34040
                     ->  Parallel Hash Join  (actual time=470.200..688.374 rows=568377 loops=3)
                           Inner Unique: true
                           Hash Cond: (p.order_id = o.id)
                           Buffers: shared hit=4292 read=172886, temp read=33985 written=34040
                           ->  Parallel Seq Scan on payments p  (actual time=0.041..139.913 rows=1709605 loops=3)
                                 Buffers: shared read=101848
                           ->  Parallel Hash  (actual time=190.774..190.774 rows=554078 loops=3)
                                 Buckets: 524288  Batches: 8  Memory Usage: 13920kB
                                 Buffers: shared hit=4274 read=71032, temp written=6436
                                 ->  Parallel Index Scan using idx_orders_created_at on orders o  (actual time=5.278..143.375 rows=554078 lo ...
                                       Index Cond: (o.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone)
                                       Buffers: shared hit=4274 read=71032
   Buffers: shared hit=4 read=12
 Planning Time: 0.391 ms
 Execution Time: 771.800 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Finalize GroupAggregate
  └── Gather Merge
        └── Sort → Partial HashAggregate
              └── Parallel Hash Join   Hash Cond: (p.order_id = o.id)
                    ├── Parallel Seq Scan on payments        (2) PROBE: mỗi payment tra bảng băm
                    └── Parallel Hash                        (1) BUILD: bảng băm các đơn tháng 9
                          └── Parallel Index Scan using idx_orders_created_at
```

```text
small side → build hash table (in memory, work_mem × hash_mem_multiplier)
large side → scan → hash(order_id) → lookup → emit matches
```
Build chạy **trước** (node Hash/Parallel Hash), probe sau. Với parallel hash, các worker cùng
build một bảng băm dùng chung trong shared memory (`/dev/shm`).

## Bottleneck

Ngay ở baseline, bảng băm đã **không vừa bộ nhớ**: `Batches: 8` (work_mem 8MB × hash_mem_multiplier 2
× số process). Mỗi batch phải ghi ra file tạm rồi đọc lại.

## Optimization Strategy A

**(experiment) work_mem = 1MB: the hash table spills to disk (Batches > 1)** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Finalize GroupAggregate  (cost=270505.95..270515.70 rows=36 width=48) (actual time=781.785..804.364 rows=36 loops=1)
   Group Key: p.payment_method, o.status
   Buffers: shared hit=4258 read=172886, temp read=34961 written=35472
   ->  Gather Merge  (cost=270505.95..270514.35 rows=72 width=48) (actual time=781.773..804.333 rows=108 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=4258 read=172886, temp read=34961 written=35472
         ->  Sort  (cost=269505.93..269506.02 rows=36 width=48) (actual time=768.979..768.983 rows=36 loops=3)
               Sort Key: p.payment_method, o.status
               Sort Method: quicksort  Memory: 28kB
               Buffers: shared hit=4258 read=172886, temp read=34961 written=35472
               ->  Partial HashAggregate  (cost=269504.55..269505.00 rows=36 width=48) (actual time=768.955..768.963 rows=36 loops=3)
                     Group Key: p.payment_method, o.status
                     Batches: 1  Memory Usage: 32kB
                     Buffers: shared hit=4242 read=172886, temp read=34961 written=35472
                     ->  Parallel Hash Join  (actual time=561.013..712.382 rows=568377 loops=3)
                           Inner Unique: true
                           Hash Cond: (p.order_id = o.id)
                           Buffers: shared hit=4242 read=172886, temp read=34961 written=35472
                           ->  Parallel Seq Scan on payments p  (actual time=0.115..142.175 rows=1709605 loops=3)
                                 Buffers: shared read=101848
                           ->  Parallel Hash  (actual time=263.449..263.450 rows=554078 loops=3)
                                 Buckets: 65536  Batches: 64  Memory Usage: 1792kB
                                 Buffers: shared hit=4224 read=71032, temp written=7484
                                 ->  Parallel Index Scan using idx_orders_created_at on orders o  (actual time=6.646..195.269 rows=554078 lo ...
                                       Index Cond: (o.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone)
                                       Buffers: shared hit=4224 read=71032
   Buffers: shared hit=4 read=12
 Planning Time: 0.674 ms
 Execution Time: 806.072 ms
```

`Batches: 64`, Memory Usage giảm còn ~1.8MB mỗi process, thời gian tăng nhẹ.

## Why It Improved

Lab này là thí nghiệm, không phải tối ưu. Strategy A giảm work_mem xuống 1MB → `Batches: 64`, chậm
hơn. Strategy B tắt Hash Join → Merge Join phải **sort 1.66 triệu đơn** (external merge, ~42MB đĩa
mỗi worker) → chậm hơn Hash Join.

## Trade-offs

- Hash Join chỉ hỗ trợ điều kiện `=`.
- Bộ nhớ: build side càng lớn càng nhiều batch; tăng work_mem cho **session** chạy báo cáo nếu cần
  (`SET LOCAL work_mem` trong transaction), không tăng toàn cục.
- Hash Join phải build xong mới trả dòng đầu tiên (startup cost cao) → không hợp với LIMIT nhỏ.

## Optimization Strategy B

**(experiment) SET enable_hashjoin = off: the alternative join** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize GroupAggregate  (cost=488394.76..488404.51 rows=36 width=48) (actual time=861.470..869.609 rows=36 loops=1)
   Group Key: p.payment_method, o.status
   Buffers: shared hit=153169 read=194321, temp read=15885 written=15924
   ->  Gather Merge  (cost=488394.76..488403.16 rows=72 width=48) (actual time=861.460..869.577 rows=108 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=153169 read=194321, temp read=15885 written=15924
         ->  Sort  (cost=487394.73..487394.82 rows=36 width=48) (actual time=853.266..853.267 rows=36 loops=3)
               Sort Key: p.payment_method, o.status
               Sort Method: quicksort  Memory: 28kB
               Buffers: shared hit=153169 read=194321, temp read=15885 written=15924
               ->  Partial HashAggregate  (cost=487393.35..487393.80 rows=36 width=48) (actual time=853.246..853.252 rows=36 loops=3)
                     Group Key: p.payment_method, o.status
                     Batches: 1  Memory Usage: 32kB
                     Buffers: shared hit=153153 read=194321, temp read=15885 written=15924
                     ->  Merge Join  (cost=294834.09..480151.51 rows=724184 width=14) (actual time=568.035..801.050 rows=568377 loops=3)
                           Inner Unique: true
                           Merge Cond: (p.order_id = o.id)
                           Buffers: shared hit=153153 read=194321, temp read=15885 written=15924
                           ->  Parallel Index Scan using idx_payments_order_id on payments p  (actual time=0.038..208.207 rows=1709605 loops ...
                                 Buffers: shared hit=18377 read=115860
                           ->  Sort  (cost=294832.25..299068.50 rows=1694499 width=12) (actual time=391.111..465.377 rows=1661956 loops=3)
                                 Sort Key: o.id
                                 Sort Method: external merge  Disk: 42360kB
                                 Buffers: shared hit=134776 read=78461, temp read=15885 written=15924
                                 ->  Index Scan using idx_orders_created_at on orders o  (actual time=0.029..305.683 rows=1662233 loops=3)
                                       Index Cond: (o.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone)
                                       Buffers: shared hit=134768 read=78459
   Buffers: shared hit=3 read=13
 Planning Time: 0.197 ms
 Execution Time: 872.772 ms
```

`Merge Join` + `Sort` (external merge trên đĩa) phía orders — chậm hơn Hash Join.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Payments of September's orders, by method and order status**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Partial HashAggregate, Parallel Hash Join, Parallel Seq Scan on public.payments p, Parallel Index Scan using idx_o` | 36 | 0 | shared hit=4308 read=172886, temp read=33985 written=34040 | 771.8 ms |

**Strategy A — (experiment) work_mem = 1MB: the hash table spills to disk (Batches > 1)**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Same query, work_mem = 1MB | `Sort, Partial HashAggregate, Parallel Hash Join, Parallel Seq Scan on public.payments p, Parallel Index Scan using idx_o` | 36 | 0 | shared hit=4258 read=172886, temp read=34961 written=35472 | 806.1 ms |

**Strategy B — (experiment) SET enable_hashjoin = off: the alternative join**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Same query with hash joins disabled | `Sort, Partial HashAggregate, Merge Join, Parallel Index Scan using idx_payments_order_id on public.payments p, Index Sca` | 36 | 0 | shared hit=153169 read=194321, temp read=15885 written=15924 | 872.8 ms |

## Reset

```sql
RESET work_mem;
RESET enable_hashjoin;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Node `Hash` / `Parallel Hash`: `Buckets`, `Batches` (1 = vừa bộ nhớ), `Memory Usage`.
- `Hash Cond` (điều kiện join) vs `Join Filter` (điều kiện kiểm tra thêm sau khi khớp hash).
- Phía nào được build: con của node Hash.

## Interview Questions

1. Hash Join hoạt động thế nào? Phía nào được build?
2. Batches > 1 nghĩa là gì? Làm sao giảm?
3. hash_mem_multiplier là gì?
4. Vì sao Hash Join không hợp với query có LIMIT nhỏ?
5. So sánh Hash Join, Merge Join, Nested Loop theo điều kiện join và kích thước dữ liệu.

## Key Takeaways

- Hash Join: tốt nhất cho hai tập lớn, điều kiện bằng, không cần thứ tự.
- Build phía nhỏ; nếu không vừa work_mem × hash_mem_multiplier thì chia batch ra đĩa.
- Các thí nghiệm enable_* chỉ để hiểu lựa chọn của planner — luôn RESET.

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
