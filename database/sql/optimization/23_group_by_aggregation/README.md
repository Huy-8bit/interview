# Lab 23 · GROUP BY: HashAggregate vs GroupAggregate

## Objective

So sánh **HashAggregate** và **GroupAggregate**: bộ nhớ, tràn đĩa, và khi nào một index biến aggregate thành dạng streaming.

## Problem

Hai báo cáo: số đơn theo trạng thái (6 nhóm) và số đơn / tổng chi tiêu theo khách (2.2 triệu nhóm).

## Baseline Query

Q1 — Few groups: orders per status

```sql
SELECT status, count(*) AS orders, sum(total_amount) AS amount
FROM orders
GROUP BY status;
```

Q2 — Millions of groups: orders per customer (2.2M groups, not fetched to the client)

```sql
SELECT user_id, count(*) AS orders, sum(total_amount) AS spent
FROM orders
GROUP BY user_id;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize GroupAggregate  (cost=237453.17..237454.76 rows=6 width=44) (actual time=280.579..282.679 rows=6 loops=1)
   Group Key: orders.status
   Buffers: shared hit=1613 read=198397
   ->  Gather Merge  (cost=237453.17..237454.57 rows=12 width=44) (actual time=280.564..282.661 rows=18 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=1613 read=198397
         ->  Sort  (cost=236453.14..236453.16 rows=6 width=44) (actual time=265.176..265.176 rows=6 loops=3)
               Sort Key: orders.status
               Sort Method: quicksort  Memory: 25kB
               Buffers: shared hit=1613 read=198397
               ->  Partial HashAggregate  (cost=236452.99..236453.07 rows=6 width=44) (actual time=265.161..265.162 rows=6 loops=3)
                     Group Key: orders.status
                     Batches: 1  Memory Usage: 24kB
                     Buffers: shared hit=1597 read=198397
                     ->  Parallel Seq Scan on orders  (actual time=0.016..104.053 rows=1666667 loops=3)
                           Buffers: shared hit=1597 read=198397
 Planning Time: 0.136 ms
 Execution Time: 282.936 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Q1 (ít nhóm): mỗi worker gom vào một bảng băm tí hon → `Partial HashAggregate` → Gather → gộp.

Q2 (nhiều nhóm):
```text
HashAggregate   Group Key: user_id
                Planned Partitions: 32  Batches: 165  Memory Usage: 16657kB  Disk Usage: 226544kB
  └── Seq Scan on orders
```
Bảng băm 2.2 triệu nhóm không vừa `work_mem × hash_mem_multiplier` (16MB) → PG13+ chia partition và tràn
đĩa (165 batch, ~220MB).

GroupAggregate thì cần đầu vào **đã sắp theo khóa nhóm**, và chỉ giữ **một nhóm** trong bộ nhớ:
```text
GroupAggregate  Group Key: user_id
  └── Index Only Scan using ix_lab23_orders_user_incl   (đã sắp theo user_id, có total_amount)
```

## Bottleneck

Q2: HashAggregate tràn đĩa 165 batch.

## Optimization Strategy A

**(experiment) work_mem = 256MB** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 HashAggregate  (cost=287495.57..304349.67 rows=1348328 width=48) (actual time=3235.214..4969.860 rows=2219487 loops=1)
   Group Key: orders.user_id
   Batches: 5  Memory Usage: 524337kB  Disk Usage: 72776kB
   Buffers: shared hit=1789 read=198205, temp read=8846 written=15689
   ->  Seq Scan on orders  (cost=0.00..249994.90 rows=5000090 width=14) (actual time=0.093..831.968 rows=5000000 loops=1)
         Buffers: shared hit=1789 read=198205
 Planning Time: 0.058 ms
 Execution Time: 5117.223 ms
```

`Batches: 5  Memory Usage: ~524MB` — ít đĩa hơn nhưng chậm hơn baseline trên lab.

## Why It Improved

- Strategy A (`work_mem = 256MB`): còn 5 batch nhưng dùng ~524MB RAM (256MB × hash_mem_multiplier 2) và trên
  lab lại **chậm hơn** — cấp phát và quản lý bảng băm khổng lồ không miễn phí.
- Strategy B (covering index): GroupAggregate streaming, không hash, không sort, không đĩa → nhanh hơn ~2.5 lần
  so với baseline.

## Trade-offs

- HashAggregate: không cần thứ tự, nhưng bộ nhớ tỉ lệ số nhóm.
- GroupAggregate: bộ nhớ hằng số, nhưng cần đầu vào có thứ tự (index, hoặc một Sort — có thể đắt).
- Index `(user_id) INCLUDE (total_amount)` gần như thay thế `idx_orders_user_id`: cân nhắc thay vì thêm.

## Optimization Strategy B

**Covering index (user_id) INCLUDE (total_amount): GroupAggregate without sort or hash** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab23_orders_user_incl ON orders (user_id) INCLUDE (total_amount);
VACUUM (ANALYZE) orders;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize GroupAggregate  (cost=237453.02..237454.61 rows=6 width=44) (actual time=343.358..371.424 rows=6 loops=1)
   Group Key: orders.status
   Buffers: shared hit=2541 read=197469
   ->  Gather Merge  (cost=237453.02..237454.42 rows=12 width=44) (actual time=343.329..371.392 rows=18 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=2541 read=197469
         ->  Sort  (cost=236452.99..236453.01 rows=6 width=44) (actual time=334.669..334.670 rows=6 loops=3)
               Sort Key: orders.status
               Sort Method: quicksort  Memory: 25kB
               Buffers: shared hit=2541 read=197469
               ->  Partial HashAggregate  (cost=236452.84..236452.92 rows=6 width=44) (actual time=334.651..334.652 rows=6 loops=3)
                     Group Key: orders.status
                     Batches: 1  Memory Usage: 24kB
                     Buffers: shared hit=2525 read=197469
                     ->  Parallel Seq Scan on orders  (actual time=0.023..151.648 rows=1666667 loops=3)
                           Buffers: shared hit=2525 read=197469
 Planning Time: 0.099 ms
 Execution Time: 372.175 ms
```

`GroupAggregate` trên `Index Only Scan using ix_lab23_orders_user_incl`, Heap Fetches 0.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Few groups: orders per status**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Partial HashAggregate, Parallel Seq Scan on public.orders` | 6 | 0 | shared hit=1613 read=198397 | 282.9 ms |
| Strategy B | `Sort, Partial HashAggregate, Parallel Seq Scan on public.orders` | 6 | 0 | shared hit=2541 read=197469 | 372.2 ms |

**Q2 — Millions of groups: orders per customer (2.2M groups, not fetched to the client)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Seq Scan on public.orders` | 2219487 | 0 | shared hit=1725 read=198269, temp read=34337 written=61684 | 3,099.8 ms |
| Strategy B | `Index Only Scan using ix_lab23_orders_user_incl on public.orders` | 2219487 | 0 | shared hit=3446622 | 1,229.0 ms |

**Strategy A — (experiment) work_mem = 256MB**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q2 with work_mem = 256MB | `Seq Scan on public.orders` | 2219487 | 0 | shared hit=1789 read=198205, temp read=8846 written=15689 | 5,117.2 ms |

HashAggregate: đầu vào bất kỳ thứ tự, bộ nhớ ~ số nhóm, tràn đĩa nếu quá lớn.
GroupAggregate: đầu vào phải sắp theo khóa nhóm, bộ nhớ ~ 1 nhóm, trả kết quả dần (tốt với LIMIT).

## Reset

```sql
RESET work_mem;
DROP INDEX IF EXISTS ix_lab23_orders_user_incl;
ANALYZE orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `HashAggregate … Batches / Memory Usage / Disk Usage` (PG13+).
- `GroupAggregate` và con của nó: Sort (đắt?) hay Index Scan (miễn phí).
- `Partial … / Finalize …`: aggregate song song.

## Interview Questions

1. HashAggregate và GroupAggregate khác nhau thế nào?
2. HashAggregate làm gì khi vượt bộ nhớ (PG13+)?
3. hash_mem_multiplier ảnh hưởng gì?
4. Index nào biến GROUP BY thành streaming aggregate?

## Key Takeaways

- Ít nhóm → HashAggregate gần như miễn phí; nhiều nhóm → lo về bộ nhớ.
- Đầu vào đã sắp theo khóa nhóm → GroupAggregate streaming.
- Nhiều work_mem hơn không đảm bảo nhanh hơn — đo.

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
