# Lab 31 · Query rewrites: count > 0, HAVING, UNION, SELECT *

## Objective

Bốn cách viết lại query phổ biến và kiểm chứng tác dụng thật của từng cách: `count(*) > 0` → `EXISTS`, `HAVING` → `WHERE`, `UNION` → `UNION ALL`, `SELECT *` → chỉ cột cần.

## Problem

Các mẫu query thường gặp trong code ứng dụng, mỗi cái làm nhiều việc hơn cần thiết — hoặc không.

## Baseline Query

Q1 — 'Are there pending orders?' written with count(*)

```sql
SELECT (SELECT count(*) FROM orders WHERE status = 'PENDING') > 0 AS has_pending;
```

Q2 — Filter on a GROUP BY column written in HAVING

```sql
SELECT status, count(*)
FROM orders
GROUP BY status
HAVING status IN ('PENDING', 'CONFIRMED');
```

Q3 — UNION (removes duplicates) of buyers and reviewers of the last day

```sql
SELECT user_id FROM orders  WHERE created_at >= '2026-09-30'
UNION
SELECT user_id FROM reviews WHERE created_at >= '2026-09-30';
```

Q4 — SELECT * of the last day's orders sorted by amount

```sql
SELECT *
FROM orders
WHERE created_at >= '2026-09-30'
ORDER BY total_amount DESC;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Result  (cost=5429.51..5429.53 rows=1 width=1) (actual time=8.576..8.640 rows=1 loops=1)
   Buffers: shared hit=1009
   InitPlan 1 (returns $1)
     ->  Finalize Aggregate  (cost=5429.50..5429.51 rows=1 width=8) (actual time=8.574..8.638 rows=1 loops=1)
           Buffers: shared hit=1009
           ->  Gather  (cost=5429.29..5429.50 rows=2 width=8) (actual time=8.572..8.636 rows=3 loops=1)
                 Workers Planned: 2
                 Workers Launched: 2
                 Buffers: shared hit=1009
                 ->  Partial Aggregate  (cost=4429.29..4429.30 rows=1 width=8) (actual time=6.841..6.841 rows=1 loops=3)
                       Buffers: shared hit=1009
                       ->  Parallel Index Only Scan using idx_orders_status_created_at on orders  (actual time=0.010..5.046 rows=86943 loops ...
                             Index Cond: (orders.status = 'PENDING'::order_status)
                             Heap Fetches: 0
                             Buffers: shared hit=1009
 Planning Time: 0.059 ms
 Execution Time: 8.650 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

- Q1 `(SELECT count(*) …) > 0`: đếm **mọi** đơn PENDING (Index Only Scan ~260k entry) chỉ để trả true/false.
- Q2 `HAVING status IN (…)`: planner **đã tự** đẩy điều kiện không chứa aggregate xuống scan
  (`Index Cond` trên `idx_orders_status_created_at`).
- Q3 `UNION`: `Append` + `HashAggregate` để khử trùng lặp ~127k dòng.
- Q4 `SELECT *` + `ORDER BY`: sort mang theo mọi cột (cả `shipping_address` jsonb) → sort tràn đĩa.

## Bottleneck

Mỗi query làm thêm việc: đếm thừa, khử trùng lặp không cần, sort dữ liệu rộng.

## Optimization Strategy A

**Rewrite each query (no DDL)** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Result  (cost=0.45..0.46 rows=1 width=1) (actual time=0.004..0.004 rows=1 loops=1)
   Buffers: shared hit=4
   InitPlan 1 (returns $0)
     ->  Index Only Scan using idx_orders_status_created_at on orders  (actual time=0.003..0.003 rows=1 loops=1)
           Index Cond: (orders.status = 'PENDING'::order_status)
           Heap Fetches: 0
           Buffers: shared hit=4
 Planning Time: 0.017 ms
 Execution Time: 0.006 ms
```

Q1 EXISTS: InitPlan dừng sau 1 dòng. Q2: plan giống hệt. Q3: không còn HashAggregate. Q4: sort nhỏ hơn.

## Why It Improved

- Q1 → `EXISTS`: dừng ở dòng đầu tiên → từ vài ms xuống micro giây.
- Q2 → WHERE: **cùng plan** — viết lại chỉ để rõ ý; planner đã làm việc này.
- Q3 → `UNION ALL`: bỏ bước HashAggregate → nhanh hơn ~2 lần (khi trùng lặp không quan trọng).
- Q4 → chỉ 3 cột: dữ liệu sort nhỏ hơn nhiều (Disk từ ~14MB/worker xuống ~4MB), plan đơn giản hơn.

## Trade-offs

- `UNION ALL` đổi ngữ nghĩa nếu trùng lặp có ý nghĩa — chỉ dùng khi chắc chắn.
- Chọn cột cụ thể ràng buộc code ứng dụng với schema chặt hơn (nhưng là thói quen đúng).

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — 'Are there pending orders?' written with count(*)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Finalize Aggregate, Partial Aggregate, Parallel Index Only Scan using idx_orders_status_created_at on public.orders` | 1 | 0 | shared hit=1009 | 8.650 ms |
| Strategy A | `Index Only Scan using idx_orders_status_created_at on public.orders` | 1 | 0 | shared hit=4 | 0.006 ms |

**Q2 — Filter on a GROUP BY column written in HAVING**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial GroupAggregate, Parallel Index Only Scan using idx_orders_status_created_at on public.orders` | 2 | 0 | shared hit=1980 | 14.9 ms |
| Strategy A | `Partial GroupAggregate, Parallel Index Only Scan using idx_orders_status_created_at on public.orders` | 2 | 0 | shared hit=1980 | 21.8 ms |

**Q3 — UNION (removes duplicates) of buyers and reviewers of the last day**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Append, Index Scan using idx_orders_created_at on public.orders, Parallel Seq Scan on public.reviews` | 114393 | 1,656,424 | shared hit=4233 read=105061 | 321.3 ms |
| Strategy A | `Index Scan using idx_orders_created_at on public.orders, Parallel Seq Scan on public.reviews` | 127307 | 1,656,424 | shared hit=4425 read=104869 | 169.0 ms |

**Q4 — SELECT * of the last day's orders sorted by amount**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Parallel Index Scan using idx_orders_created_at on public.orders` | 96578 | 0 | shared hit=4302, temp read=2716 written=2718 | 59.6 ms |
| Strategy A | `Index Scan using idx_orders_created_at on public.orders` | 96578 | 0 | shared hit=4134, temp read=532 written=533 | 43.2 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Aggregate trên hàng trăm nghìn dòng để trả một boolean.
- `HashAggregate` / `Unique` trên `Append` của UNION.
- `Sort … Disk:` và `width=` của các node — độ rộng dòng.

## Interview Questions

1. Vì sao EXISTS nhanh hơn count(*) > 0?
2. Planner có tự đẩy điều kiện HAVING xuống WHERE không? Khi nào không thể?
3. UNION và UNION ALL khác nhau thế nào về chi phí và ngữ nghĩa?
4. SELECT * ảnh hưởng thế nào đến sort, Index Only Scan, mạng?

## Key Takeaways

- Hỏi 'có tồn tại không' bằng EXISTS.
- Planner tự làm nhiều phép viết lại — kiểm tra plan trước khi 'tối ưu'.
- UNION ALL khi không cần khử trùng lặp.
- Chỉ chọn cột cần dùng.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
