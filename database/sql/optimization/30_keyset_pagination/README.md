# Lab 30 · Keyset (seek) pagination

## Objective

Dùng **keyset (seek) pagination**: chi phí không phụ thuộc trang thứ mấy; so sánh row value comparison, tie-breaker và Incremental Sort.

## Problem

Phân trang đơn hàng mới nhất theo `(created_at DESC, id DESC)` — id là tie-breaker để không mất/lặp dòng khi trùng created_at.

## Baseline Query

Q1 — Deep page with OFFSET (for contrast)

```sql
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 50 OFFSET 1000000;
```

Q2 — Next page after a cursor (keyset)

```sql
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE (created_at, id) < ('2026-03-01 00:00:00+00', 1500000)
ORDER BY created_at DESC, id DESC
LIMIT 50;
```

Q3 — Keyset on the primary key

```sql
SELECT id, order_number, total_amount
FROM orders
WHERE id > 4000000
ORDER BY id
LIMIT 50;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Limit  (cost=103015.91..103021.06 rows=50 width=46) (actual time=387.761..387.773 rows=50 loops=1)
   Buffers: shared hit=4112 read=41385 written=15
   ->  Incremental Sort  (cost=0.50..515080.63 rows=5000030 width=46) (actual time=0.044..369.378 rows=1000050 loops=1)
         Sort Key: orders.created_at DESC, orders.id DESC
         Presorted Key: orders.created_at
         Full-sort Groups: 31252  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
         Buffers: shared hit=4112 read=41385 written=15
         ->  Index Scan Backward using idx_orders_created_at on orders  (actual time=0.030..264.459 rows=1000051 loops=1)
               Buffers: shared hit=4112 read=41385 written=15
 Planning Time: 0.112 ms
 Execution Time: 387.995 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

OFFSET (Q1): Incremental Sort trên 1,000,050 dòng rồi bỏ đi.

Keyset (Q2): "các dòng nhỏ hơn con trỏ (created_at, id) của dòng cuối trang trước":
```text
Limit (50)
  └── Incremental Sort   Presorted Key: created_at
        └── Index Scan Backward using idx_orders_created_at
              Index Cond: (created_at <= '2026-03-01 ...')
              Filter: (ROW(created_at, id) < ROW('2026-03-01 ...', 1500000))
```
Index seek thẳng tới con trỏ, đọc ~51 dòng; Incremental Sort sắp lại các nhóm trùng created_at theo id.

## Bottleneck

Q1 (OFFSET) đọc 1 triệu dòng. Keyset baseline đã nhanh (micro giây).

## Optimization Strategy A

**Index on (created_at DESC, id DESC): the row comparison becomes an index range** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab30_orders_created_id ON orders (created_at DESC, id DESC);
ANALYZE orders;
```

## Result

AFTER Strategy A — Q1:

```text
 Limit  (cost=103015.11..103020.26 rows=50 width=46) (actual time=299.344..299.352 rows=50 loops=1)
   Buffers: shared hit=4790 read=40707 written=2
   ->  Incremental Sort  (cost=0.50..515086.21 rows=5000123 width=46) (actual time=0.031..282.046 rows=1000050 loops=1)
         Sort Key: orders.created_at DESC, orders.id DESC
         Presorted Key: orders.created_at
         Full-sort Groups: 31252  Sort Method: quicksort  Average Memory: 27kB  Peak Memory: 27kB
         Buffers: shared hit=4790 read=40707 written=2
         ->  Index Scan Backward using idx_orders_created_at on orders  (actual time=0.017..193.267 rows=1000051 loops=1)
               Buffers: shared hit=4790 read=40707 written=2
 Planning Time: 0.058 ms
 Execution Time: 299.510 ms
```

Plan không đổi — keyset trên baseline đã đọc đúng ~50 dòng.

## Why It Improved

Keyset đã nhanh ngay trên baseline nhờ Incremental Sort (PG13+): chỉ cần sort vài nhóm nhỏ.
Strategy A tạo index `(created_at DESC, id DESC)` — planner **không đổi plan**, vì plan hiện tại đã đọc
đúng ~50 dòng. Index này chỉ đáng giá khi có **rất nhiều** dòng trùng created_at (khi đó Filter phải
bỏ qua nhiều dòng) hoặc trên PostgreSQL cũ không có Incremental Sort.

## Trade-offs

- Keyset không nhảy thẳng tới "trang 5,000" được — chỉ "trang sau / trang trước". Phù hợp infinite scroll, API cursor.
- Con trỏ phải chứa **toàn bộ** khóa sắp xếp (kể cả tie-breaker duy nhất).
- Đổi chiều sắp xếp / bộ lọc → con trỏ khác.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Deep page with OFFSET (for contrast)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Incremental Sort, Index Scan Backward using idx_orders_created_at on public.orders` | 50 | 0 | shared hit=4112 read=41385 written=15 | 388.0 ms |
| Strategy A | `Incremental Sort, Index Scan Backward using idx_orders_created_at on public.orders` | 50 | 0 | shared hit=4790 read=40707 written=2 | 299.5 ms |

**Q2 — Next page after a cursor (keyset)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Incremental Sort, Index Scan Backward using idx_orders_created_at on public.orders` | 50 | 0 | shared hit=6 | 0.020 ms |
| Strategy A | `Incremental Sort, Index Scan Backward using idx_orders_created_at on public.orders` | 50 | 0 | shared hit=6 | 0.019 ms |

**Q3 — Keyset on the primary key**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using pk_orders on public.orders` | 50 | 0 | shared hit=7 | 0.012 ms |
| Strategy A | `Index Scan using pk_orders on public.orders` | 50 | 0 | shared hit=7 | 0.015 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab30_orders_created_id;
ANALYZE orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- OFFSET: `actual rows` dưới Limit = OFFSET + LIMIT.
- Keyset: `Index Cond` trên khóa sắp xếp, `actual rows` ≈ LIMIT.
- `ROW(a, b) < ROW(x, y)`: row value comparison (đúng ngữ nghĩa tie-breaker).

## Interview Questions

1. Keyset pagination hoạt động thế nào? Vì sao cần tie-breaker?
2. Vì sao `WHERE created_at < X OR (created_at = X AND id < Y)` tương đương `(created_at, id) < (X, Y)`?
3. Nhược điểm của keyset so với OFFSET?
4. Incremental Sort giúp gì trong keyset pagination?

## Key Takeaways

- Keyset: chi phí hằng số theo trang.
- Con trỏ = giá trị khóa sắp xếp của dòng cuối, có tie-breaker duy nhất.
- Kiểm tra plan trước khi thêm index 'cho chắc'.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
