# Lab 10 · Function on an indexed column (sargable queries)

## Objective

Nhận ra các điều kiện **không sargable** (hàm/ép kiểu trên cột) và viết lại chúng để dùng được index.

## Problem

Báo cáo "đơn hàng trong một ngày / một tháng" được viết bằng `created_at::date = ...`,
`date_trunc('day', created_at) = ...`, `extract(year/month ...)`. Có index `idx_orders_created_at`
nhưng các query vẫn chậm.

## Baseline Query

Q1 — Orders of one day, written with a cast

```sql
SELECT count(*)
FROM orders
WHERE created_at::date = '2026-06-15';
```

Q2 — Orders of one day, written with date_trunc

```sql
SELECT count(*)
FROM orders
WHERE date_trunc('day', created_at) = '2026-06-15';
```

Q3 — Orders of February 2026, written with extract

```sql
SELECT count(*)
FROM orders
WHERE extract(year FROM created_at) = 2026
  AND extract(month FROM created_at) = 2;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=72404.41..72404.42 rows=1 width=8) (actual time=88.258..91.033 rows=1 loops=1)
   Buffers: shared hit=13691
   ->  Gather  (cost=72404.20..72404.41 rows=2 width=8) (actual time=88.216..91.031 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=13691
         ->  Partial Aggregate  (cost=71404.20..71404.21 rows=1 width=8) (actual time=86.479..86.479 rows=1 loops=3)
               Buffers: shared hit=13691
               ->  Parallel Index Only Scan using idx_orders_created_at on orders  (actual time=36.998..86.424 rows=2584 loops=3)
                     Filter: ((orders.created_at)::date = '2026-06-15'::date)
                     Rows Removed by Filter: 1664082
                     Heap Fetches: 0
                     Buffers: shared hit=13691
 Planning Time: 0.070 ms
 Execution Time: 91.046 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Finalize Aggregate
  └── Gather
        └── Partial Aggregate
              └── Parallel Index Only Scan using idx_orders_created_at
                    Filter: ((created_at)::date = '2026-06-15'::date)
                    Rows Removed by Filter: 1664082
```
Planner vẫn dùng index — nhưng chỉ vì index nhỏ hơn bảng: nó **quét toàn bộ** 5 triệu entry và
áp dụng `Filter` trên từng entry. `Index Cond` trống: không có điểm seek.

## Bottleneck

Quét toàn bộ index (~13.7k trang), `Rows Removed by Filter` ~5 triệu. Với `extract()`, planner còn
**không có statistics** cho biểu thức: ước lượng ~156 dòng trong khi thực tế 123,400 — sai gần
1,000 lần, đủ để làm hỏng plan của một query lớn hơn có join.

## Optimization Strategy A

**Rewrite as a half-open range on the bare column (sargable)** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=195.23..195.24 rows=1 width=8) (actual time=0.498..0.499 rows=1 loops=1)
   Buffers: shared hit=25
   ->  Index Only Scan using idx_orders_created_at on orders  (actual time=0.004..0.321 rows=7753 loops=1)
         Index Cond: ((orders.created_at >= '2026-06-15 00:00:00+00'::timestamp with time zone) AND (orders.created_at < '2026-06-16 00:00:0 ...
         Heap Fetches: 0
         Buffers: shared hit=25
 Planning Time: 0.012 ms
 Execution Time: 0.501 ms
```

Cả ba query: `Index Only Scan` với `Index Cond` trên `created_at`, đọc vài chục trang.

## Why It Improved

Viết thành khoảng nửa mở `created_at >= '2026-06-15' AND created_at < '2026-06-16'`: cột đứng một
mình → `Index Cond` → chỉ đọc entry của ngày đó (~25 trang). Ước lượng lấy từ histogram của
`created_at` nên chính xác (116k ước lượng vs 123k thực tế cho tháng 2).

## Trade-offs

- Khoảng nửa mở `[start, end)` an toàn với mọi độ chính xác (tránh `23:59:59.999`).
- `created_at::date` phụ thuộc `TimeZone` của session: khi viết lại thành range, phải chọn rõ múi giờ
  của "ngày" (lab dùng UTC).

## Optimization Strategy B

**Expression index on the UTC date (when the query cannot be changed)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
-- This fails on purpose: the cast depends on the session TimeZone
DO $$
BEGIN
  EXECUTE 'CREATE INDEX ix_lab10_should_fail ON orders ((created_at::date))';
EXCEPTION WHEN others THEN
  RAISE NOTICE 'expected error: %', SQLERRM;
END $$;

CREATE INDEX ix_lab10_orders_created_utc_date ON orders (((created_at AT TIME ZONE 'UTC')::date));
ANALYZE orders;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=601.13..601.14 rows=1 width=8) (actual time=0.601..0.601 rows=1 loops=1)
   Buffers: shared hit=320
   ->  Index Scan using ix_lab10_orders_created_utc_date on orders  (actual time=0.005..0.427 rows=7753 loops=1)
         Index Cond: (((orders.created_at AT TIME ZONE 'UTC'::text))::date = '2026-06-15'::date)
         Buffers: shared hit=320
 Planning Time: 0.030 ms
 Execution Time: 0.610 ms
```

Khi không sửa được query (code bên thứ ba): `CREATE INDEX ... ((created_at::date))` **thất bại**
(`functions in index expression must be marked IMMUTABLE` — kết quả cast phụ thuộc TimeZone).
Index trên `((created_at AT TIME ZONE 'UTC')::date)` hợp lệ và query viết đúng biểu thức đó dùng
được nó — trả giá thêm một index ~33 MB.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Orders of one day, written with a cast**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Index Only Scan using idx_orders_created_at on public.orders` | 1 | 1,664,082 | shared hit=13691 | 91.0 ms |
| Strategy A | `Index Only Scan using idx_orders_created_at on public.orders` | 1 | 0 | shared hit=25 | 0.501 ms |

**Q2 — Orders of one day, written with date_trunc**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Index Only Scan using idx_orders_created_at on public.orders` | 1 | 1,664,082 | shared hit=13691 | 127.2 ms |
| Strategy A | `Index Only Scan using idx_orders_created_at on public.orders` | 1 | 0 | shared hit=25 | 0.476 ms |

**Q3 — Orders of February 2026, written with extract**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Index Only Scan using idx_orders_created_at on public.orders` | 1 | 1,625,533 | shared hit=13691 | 239.6 ms |
| Strategy A | `Index Only Scan using idx_orders_created_at on public.orders` | 1 | 0 | shared hit=341 | 7.691 ms |

**Strategy B — Expression index on the UTC date (when the query cannot be changed)**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Query using the indexed expression | `Index Scan using ix_lab10_orders_created_utc_date on public.orders` | 1 | 0 | shared hit=320 | 0.610 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
DROP INDEX IF EXISTS ix_lab10_orders_created_utc_date;
ANALYZE orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Filter` chứa hàm/cast của cột, `Index Cond` trống, `Rows Removed by Filter` lớn.
- Ước lượng `rows=` vô lý cho điều kiện trên biểu thức (không có statistics).

## Interview Questions

1. Sargable nghĩa là gì? Cho 3 ví dụ điều kiện không sargable và cách viết lại.
2. Vì sao `created_at::date` không thể index trực tiếp với timestamptz?
3. Vì sao nên dùng khoảng nửa mở cho truy vấn theo ngày?
4. Planner ước lượng số dòng cho `extract(month FROM created_at) = 2` như thế nào?

## Key Takeaways

- Đừng bọc cột trong hàm ở WHERE; biến đổi giá trị so sánh thay vì cột.
- Index vẫn có thể 'được dùng' mà không giúp gì: xem Index Cond, không chỉ tên index.
- Điều kiện trên biểu thức không có statistics → ước lượng sai → plan sai.

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
