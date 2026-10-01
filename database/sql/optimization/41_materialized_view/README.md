# Lab 41 · Materialized view: precompute an expensive aggregate

## Objective

Dùng **materialized view** để tính trước một aggregate đắt, và hiểu đánh đổi giữa độ tươi và tốc độ.

## Problem

Dashboard doanh thu theo ngày của quý 3/2026, tính từ 5 triệu đơn mỗi lần tải trang.

## Baseline Query

Q1 — Daily revenue dashboard (Q3 2026) computed from 5M orders

```sql
SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
       count(*)          AS orders,
       sum(total_amount) AS revenue
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-07-01' AND created_at < '2026-10-01'
GROUP BY 1
ORDER BY 1;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 GroupAggregate  (cost=374889.21..420041.51 rows=1641902 width=44) (actual time=584.695..679.694 rows=90 loops=1)
   Group Key: (((orders.created_at AT TIME ZONE 'UTC'::text))::date)
   Buffers: shared hit=66 read=117471, temp read=2761 written=2769
   ->  Sort  (cost=374889.21..378993.96 rows=1641902 width=10) (actual time=584.023..618.400 rows=1074494 loops=1)
         Sort Key: (((orders.created_at AT TIME ZONE 'UTC'::text))::date)
         Sort Method: external merge  Disk: 22088kB
         Buffers: shared hit=66 read=117471, temp read=2761 written=2769
         ->  Index Scan using idx_orders_created_at on orders  (actual time=3.345..530.858 rows=1074494 loops=1)
               Index Cond: ((orders.created_at >= '2026-07-01 00:00:00+00'::timestamp with time zone) AND (orders.created_at < '2026-10-01 0 ...
               Filter: (orders.status = 'COMPLETED'::order_status)
               Rows Removed by Filter: 1674473
               Buffers: shared hit=66 read=117471
   Buffers: shared read=4
 Planning Time: 0.159 ms
 Execution Time: 681.566 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Live query:
```text
GroupAggregate / HashAggregate (day)
  └── Index Scan on orders (created_at trong quý 3, lọc status)    <- hàng trăm nghìn dòng
```
Materialized view lưu **kết quả** (ngày × trạng thái, ~2.4k dòng) như một bảng; truy vấn dashboard đọc
~90 dòng qua unique index của MV.

## Bottleneck

Mỗi lần tải dashboard aggregate hàng trăm nghìn đơn.

## Optimization Strategy A

**CREATE MATERIALIZED VIEW + unique index (for REFRESH CONCURRENTLY)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE MATERIALIZED VIEW mv_lab41_daily_revenue AS
SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
       status,
       count(*)          AS orders,
       sum(total_amount) AS revenue
FROM orders
GROUP BY 1, 2;
CREATE UNIQUE INDEX ix_lab41_mv_daily_revenue ON mv_lab41_daily_revenue (day, status);
ANALYZE mv_lab41_daily_revenue;

-- Refresh cost: the whole query runs again (CONCURRENTLY = compute + diff + apply)
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_lab41_daily_revenue;
```

## Result

AFTER Strategy A — Q1:

```text
 Index Scan using ix_lab41_mv_daily_revenue on mv_lab41_daily_revenue  (actual time=0.005..0.020 rows=90 loops=1)
   Index Cond: ((mv_lab41_daily_revenue.day >= '2026-07-01'::date) AND (mv_lab41_daily_revenue.day < '2026-10-01'::date) AND (mv_lab41_daily ...
   Buffers: shared hit=89
   Buffers: shared hit=6
 Planning Time: 0.016 ms
 Execution Time: 0.023 ms
```

Dashboard đọc từ `mv_lab41_daily_revenue` qua `ix_lab41_mv_daily_revenue`: ~90 dòng.

## Why It Improved

Đọc từ MV: Index Scan trên ~90 dòng, micro giây đến dưới 1 ms thay vì hàng trăm ms. MV chỉ ~336 kB.

## Trade-offs

- Dữ liệu **cũ** giữa hai lần `REFRESH`; refresh chạy lại toàn bộ query (không incremental).
- `REFRESH MATERIALIZED VIEW CONCURRENTLY` không chặn người đọc nhưng cần một UNIQUE index và chậm hơn
  (tính kết quả mới, so sánh, áp dụng phần khác biệt).
- Cần lập lịch refresh (cron / pg_cron); nếu cần số liệu thời gian thực, dùng bảng tổng hợp cập nhật
  bằng trigger hoặc ở tầng ứng dụng.
- MV nằm trên primary và được replicate sang replica như bảng thường (refresh sinh WAL).

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Daily revenue dashboard (Q3 2026) computed from 5M orders**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Index Scan using idx_orders_created_at on public.orders` | 90 | 1,674,473 | shared hit=66 read=117471, temp read=2761 written=2769 | 681.6 ms |
| Strategy A | `Index Scan using ix_lab41_mv_daily_revenue on public.mv_lab41_daily_revenue` | 90 | 0 | shared hit=89 | 0.023 ms |

## Reset

```sql
DROP MATERIALIZED VIEW IF EXISTS mv_lab41_daily_revenue;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Live: số dòng đi vào node aggregate.
- MV: `Index Scan using ix_lab41_mv_daily_revenue` và Buffers rất nhỏ.
- Thời gian `REFRESH` (chạy `02_optimize.sql` trong psql với `\timing on`).

## Interview Questions

1. Materialized view khác view thường thế nào?
2. REFRESH CONCURRENTLY cần điều kiện gì? Đánh đổi là gì?
3. Khi nào dùng materialized view, khi nào dùng bảng tổng hợp cập nhật bằng trigger?
4. Materialized view có tự cập nhật khi bảng gốc thay đổi không?

## Key Takeaways

- Materialized view đổi độ tươi lấy tốc độ đọc.
- REFRESH CONCURRENTLY cần unique index, không chặn người đọc.
- Lập lịch refresh phù hợp với yêu cầu nghiệp vụ về độ trễ dữ liệu.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
