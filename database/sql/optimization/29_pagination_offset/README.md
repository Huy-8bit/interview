# Lab 29 · Pagination with OFFSET: the cost of deep pages

## Objective

Đo chi phí của `LIMIT … OFFSET` khi trang càng sâu, và kỹ thuật **deferred join** (late row lookup) — chỉ hiệu quả với index phù hợp.

## Problem

Danh sách đơn hàng mới nhất, 50 dòng/trang: trang 1, trang 2,001, trang 20,001.

## Baseline Query

Q1 — Page 1 (OFFSET 0)

```sql
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 0;
```

Q2 — Page 2,001 (OFFSET 100,000)

```sql
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 100000;
```

Q3 — Page 20,001 (OFFSET 1,000,000)

```sql
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 1000000;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Limit  (cost=0.43..3.33 rows=50 width=46) (actual time=0.002..0.009 rows=50 loops=1)
   Buffers: shared hit=6
   ->  Index Scan Backward using idx_orders_created_at on orders  (actual time=0.002..0.007 rows=50 loops=1)
         Buffers: shared hit=6
 Planning Time: 0.012 ms
 Execution Time: 0.012 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Limit (50)
  └── Index Scan Backward using idx_orders_created_at   actual rows = OFFSET + 50
```
OFFSET không "nhảy" được: mọi dòng bị bỏ qua vẫn được đọc (từ index **và heap**) rồi bị Limit vứt đi.
Trang 20,001 đọc 1,000,050 dòng để trả 50.

## Bottleneck

Chi phí tuyến tính theo OFFSET: trang 20,001 ~ 45k buffers, hàng trăm ms.

## Optimization Strategy A

**(experiment) 'deferred join' WITHOUT a suitable index** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Sort  (cost=58154.31..58154.44 rows=50 width=46) (actual time=214.200..214.202 rows=50 loops=1)
   Sort Key: o.created_at DESC
   Sort Method: quicksort  Memory: 28kB
   Buffers: shared hit=4672 read=41025
   ->  Nested Loop  (cost=58017.43..58152.90 rows=50 width=46) (actual time=214.151..214.190 rows=50 loops=1)
         Inner Unique: true
         Buffers: shared hit=4672 read=41025
         ->  Limit  (cost=58017.00..58019.90 rows=50 width=16) (actual time=214.136..214.146 rows=50 loops=1)
               Buffers: shared hit=4472 read=41025
               ->  Index Scan Backward using idx_orders_created_at on orders  (actual time=0.020..198.576 rows=1000050 loops=1)
                     Buffers: shared hit=4472 read=41025
         ->  Index Scan using pk_orders on orders o  (cost=0.43..2.65 rows=1 width=46) (actual time=0.001..0.001 rows=1 loops=50)
               Index Cond: (o.id = orders.id)
               Buffers: shared hit=200
   Buffers: shared hit=8
 Planning Time: 0.276 ms
 Execution Time: 214.216 ms
```

Deferred join không có covering index: vẫn Index Scan Backward đọc heap cho mọi dòng bị bỏ qua.

## Why It Improved

Deferred join: phân trang trên subquery chỉ lấy `id`, rồi join lấy 50 dòng đầy đủ.

- Strategy A (không có index phù hợp): subquery vẫn **Index Scan** (không phải Index Only) vì
  `idx_orders_created_at` không chứa `id` → vẫn đọc heap cho 1 triệu dòng bị bỏ qua → cải thiện rất ít.
- Strategy B (`(created_at DESC) INCLUDE (id)` + VACUUM): subquery thành **Index Only Scan, Heap Fetches 0**
  → bỏ qua 1 triệu entry chỉ trên các trang index dày đặc, rồi 50 lần tra heap: nhanh hơn ~8 lần ở trang
  sâu nhất, ~3 lần ở trang giữa.

## Trade-offs

- Vẫn là O(OFFSET) — chỉ rẻ hơn mỗi dòng. Giải pháp thật sự cho trang sâu: keyset pagination (Lab 30),
  hoặc giới hạn độ sâu trang về mặt nghiệp vụ.
- `SELECT count(*)` để hiển thị "tổng số trang" cũng đắt trên bảng lớn — cân nhắc ước lượng
  (`pg_class.reltuples`) hoặc bỏ tổng số trang.

## Optimization Strategy B

**Deferred join + index (created_at DESC) INCLUDE (id)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab29_orders_created_incl_id ON orders (created_at DESC) INCLUDE (id);
VACUUM (ANALYZE) orders;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Sort  (cost=135.80..135.93 rows=50 width=46) (actual time=0.043..0.044 rows=50 loops=1)
   Sort Key: o.created_at DESC
   Sort Method: quicksort  Memory: 28kB
   Buffers: shared hit=204
   ->  Nested Loop  (cost=0.86..134.39 rows=50 width=46) (actual time=0.006..0.038 rows=50 loops=1)
         Inner Unique: true
         Buffers: shared hit=204
         ->  Limit  (cost=0.43..1.39 rows=50 width=16) (actual time=0.003..0.007 rows=50 loops=1)
               Buffers: shared hit=4
               ->  Index Only Scan using ix_lab29_orders_created_incl_id on orders  (actual time=0.003..0.005 rows=50 loops=1)
                     Heap Fetches: 0
                     Buffers: shared hit=4
         ->  Index Scan using pk_orders on orders o  (cost=0.43..2.65 rows=1 width=46) (actual time=0.000..0.000 rows=1 loops=50)
               Index Cond: (o.id = orders.id)
               Buffers: shared hit=200
   Buffers: shared hit=8
 Planning Time: 0.059 ms
 Execution Time: 0.051 ms
```

Subquery: `Index Only Scan using ix_lab29_orders_created_incl_id`, Heap Fetches 0; trang sâu nhanh hơn nhiều lần.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Page 1 (OFFSET 0)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan Backward using idx_orders_created_at on public.orders` | 50 | 0 | shared hit=6 | 0.012 ms |
| Strategy B | `Nested Loop, Index Only Scan using ix_lab29_orders_created_incl_id on public.orders, Index Scan using pk_orders on publi` | 50 | 0 | shared hit=204 | 0.051 ms |

**Q2 — Page 2,001 (OFFSET 100,000)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan Backward using idx_orders_created_at on public.orders` | 50 | 0 | shared hit=4556 | 13.7 ms |
| Strategy B | `Nested Loop, Index Only Scan using ix_lab29_orders_created_incl_id on public.orders, Index Scan using pk_orders on publi` | 50 | 0 | shared hit=588 | 5.112 ms |

**Q3 — Page 20,001 (OFFSET 1,000,000)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan Backward using idx_orders_created_at on public.orders` | 50 | 0 | shared hit=4428 read=41069 | 404.2 ms |
| Strategy B | `Nested Loop, Index Only Scan using ix_lab29_orders_created_incl_id on public.orders, Index Scan using pk_orders on publi` | 50 | 0 | shared hit=4037 | 51.4 ms |

**Strategy A — (experiment) 'deferred join' WITHOUT a suitable index**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Deferred join, OFFSET 1,000,000 | `Nested Loop, Index Scan Backward using idx_orders_created_at on public.orders, Index Scan using pk_orders on public.orde` | 50 | 0 | shared hit=4672 read=41025 | 214.2 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
DROP INDEX IF EXISTS ix_lab29_orders_created_incl_id;
ANALYZE orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `actual rows` của scan dưới Limit = OFFSET + LIMIT.
- Index Scan vs Index Only Scan trong subquery của deferred join.

## Interview Questions

1. Vì sao OFFSET lớn chậm?
2. Deferred join là gì? Điều kiện để nó hiệu quả?
3. Keyset pagination khác OFFSET thế nào? Nhược điểm của keyset?
4. Làm sao hiển thị tổng số trang mà không count(*) mỗi request?

## Key Takeaways

- OFFSET đọc và vứt bỏ mọi dòng phía trước.
- Một kỹ thuật chỉ hiệu quả khi plan bên dưới hỗ trợ nó (ở đây: Index Only Scan).
- Trang sâu: keyset pagination.

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
