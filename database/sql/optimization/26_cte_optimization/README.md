# Lab 26 · CTE: inlined, MATERIALIZED, NOT MATERIALIZED

## Objective

Hiểu CTE (`WITH`) được inline hay materialize, `MATERIALIZED` / `NOT MATERIALIZED`, và lịch sử 'optimization fence'.

## Problem

Hai cách dùng CTE phổ biến: lọc một CTE dùng một lần, và dùng một CTE tốn kém hai lần (so với trung bình của chính nó).

## Baseline Query

Q1 — CTE referenced once: inlined by the planner (PostgreSQL 12+)

```sql
WITH recent AS (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 2732269;
```

Q2 — CTE referenced twice: computed once (materialized) by default

```sql
WITH user_totals AS (
  SELECT user_id, sum(total_amount) AS spent
  FROM orders
  WHERE created_at >= '2026-09-01'
  GROUP BY user_id
)
SELECT count(*) AS above_average_customers
FROM user_totals
WHERE spent > (SELECT avg(spent) FROM user_totals);
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Index Scan using idx_orders_user_id on orders  (cost=0.43..4.49 rows=2 width=18) (actual time=0.012..0.013 rows=1 loops=1)
   Index Cond: (orders.user_id = 2732269)
   Filter: (orders.created_at >= '2026-08-01 00:00:00+00'::timestamp with time zone)
   Buffers: shared hit=4
 Planning Time: 0.067 ms
 Execution Time: 0.022 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

**Trước PostgreSQL 12**, mọi CTE là *optimization fence*: được tính toàn bộ, lưu lại, và điều kiện bên
ngoài không được đẩy vào. **Từ PG12**: CTE không đệ quy, không có side effect, **dùng đúng một lần** được
inline như một subquery; dùng từ hai lần trở lên thì mặc định materialize.

Q1 (dùng một lần, đã inline):
```text
Index Scan using idx_orders_user_id on orders
  Index Cond: (user_id = 2732269)
  Filter: (created_at >= '2026-08-01')
```
Q2 (dùng hai lần, materialize):
```text
Aggregate
  CTE user_totals → HashAggregate ← Index Scan on orders     (tính MỘT lần)
  InitPlan → Aggregate ← CTE Scan on user_totals             (lần dùng 1: avg)
  └── CTE Scan on user_totals  Filter: spent > avg            (lần dùng 2)
```

## Bottleneck

Không có ở baseline — mặc định của planner đã đúng cho cả hai. Lab cho thấy điều gì xảy ra khi ép ngược lại.

## Optimization Strategy A

**(experiment) AS MATERIALIZED on the single-use CTE** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 CTE Scan on recent  (cost=140801.18..193150.89 rows=11633 width=28) (actual time=460.925..792.196 rows=1 loops=1)
   Filter: (recent.user_id = 2732269)
   Rows Removed by Filter: 2349885
   Buffers: shared hit=56 read=100418, temp written=86654
   CTE recent
     ->  Index Scan using idx_orders_created_at on orders  (actual time=0.045..388.283 rows=2349886 loops=1)
           Index Cond: (orders.created_at >= '2026-08-01 00:00:00+00'::timestamp with time zone)
           Buffers: shared hit=56 read=100418
 Planning Time: 0.082 ms
 Execution Time: 840.926 ms
```

`CTE Scan on recent` + `Rows Removed by Filter: 2349885`: fence chặn điều kiện user_id.

## Why It Improved

- Strategy A (`AS MATERIALIZED` cho Q1): CTE bị tính toàn bộ (2.35 triệu đơn từ tháng 8), rồi lọc lại
  để giữ 1 dòng — từ micro giây lên gần 1 giây.
- Strategy B (`AS NOT MATERIALIZED` cho Q2): mỗi lần tham chiếu là một bản sao của subquery → GROUP BY
  user_id chạy **hai lần** (cả hai đều tràn đĩa) — chậm hơn ~1.5 lần.

## Trade-offs

- `MATERIALIZED` vẫn hữu ích: ép tính một lần một biểu thức đắt / hàm volatile, hoặc chặn planner chọn
  một plan tệ do ước lượng sai bên trong.
- `NOT MATERIALIZED` hữu ích khi CTE dùng nhiều lần nhưng mỗi lần chỉ cần một phần nhỏ (điều kiện khác nhau
  đẩy được vào từng bản).

## Optimization Strategy B

**(experiment) NOT MATERIALIZED on the CTE that is used twice** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=398311.61..398311.62 rows=1 width=8) (actual time=2209.203..2209.204 rows=1 loops=1)
   Buffers: shared hit=86 read=142064, temp read=16714 written=39836
   InitPlan 1 (returns $0)
     ->  Aggregate  (cost=202373.10..202373.11 rows=1 width=32) (actual time=1194.830..1194.830 rows=1 loops=1)
           Buffers: shared hit=43 read=71032, temp read=8357 written=19918
           ->  HashAggregate  (cost=158696.20..188584.67 rows=1103074 width=40) (actual time=826.968..1165.780 rows=1110052 loops=1)
                 Group Key: orders_1.user_id
                 Planned Partitions: 32  Batches: 33  Memory Usage: 16657kB  Disk Usage: 95312kB
                 Buffers: shared hit=43 read=71032, temp read=8357 written=19918
                 ->  Index Scan using idx_orders_created_at on orders orders_1  (actual time=0.030..299.699 rows=1662233 loops=1)
                       Index Cond: (orders_1.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone)
                       Buffers: shared hit=43 read=71032
   ->  HashAggregate  (cost=158696.20..191342.36 rows=367691 width=40) (actual time=1852.523..2203.182 rows=291307 loops=1)
         Group Key: orders.user_id
         Filter: (sum(orders.total_amount) > $0)
         Planned Partitions: 32  Batches: 33  Memory Usage: 16657kB  Disk Usage: 95312kB
         Rows Removed by Filter: 818745
         Buffers: shared hit=86 read=142064, temp read=16714 written=39836
         ->  Index Scan using idx_orders_created_at on orders  (actual time=0.096..290.814 rows=1662233 loops=1)
               Index Cond: (orders.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone)
               Buffers: shared hit=43 read=71032
 Planning Time: 0.147 ms
 Execution Time: 2223.038 ms
```

Cây con `HashAggregate ← Index Scan on orders` xuất hiện hai lần trong plan.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — CTE referenced once: inlined by the planner (PostgreSQL 12+)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using idx_orders_user_id on public.orders` | 1 | 0 | shared hit=4 | 0.022 ms |

**Q2 — CTE referenced twice: computed once (materialized) by default**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `HashAggregate, Index Scan using idx_orders_created_at on public.orders, Aggregate, CTE Scan on user_totals user_totals_1` | 1 | 818,745 | shared hit=43 read=71032, temp read=11743 written=23304 | 1,454.9 ms |

**Strategy A — (experiment) AS MATERIALIZED on the single-use CTE**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q1 with AS MATERIALIZED | `Index Scan using idx_orders_created_at on public.orders` | 1 | 2,349,885 | shared hit=56 read=100418, temp written=86654 | 840.9 ms |

**Strategy B — (experiment) NOT MATERIALIZED on the CTE that is used twice**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q2 with AS NOT MATERIALIZED | `Aggregate, HashAggregate, Index Scan using idx_orders_created_at on public.orders orders_1, Index Scan using idx_orders_` | 1 | 818,745 | shared hit=86 read=142064, temp read=16714 written=39836 | 2,223.0 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
-- (nothing to undo: query rewrite only)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Có node `CTE <name>` + `CTE Scan` → materialized; không có → inlined.
- `Filter` trên CTE Scan với `Rows Removed by Filter` lớn → điều kiện không được đẩy vào.

## Interview Questions

1. Optimization fence là gì? PG12 thay đổi gì?
2. Khi nào CTE được inline, khi nào materialize?
3. Khi nào nên viết MATERIALIZED / NOT MATERIALIZED?
4. CTE có INSERT/UPDATE (data-modifying) có bị inline không?

## Key Takeaways

- PG12+: CTE dùng một lần được inline — điều kiện bên ngoài được đẩy vào.
- CTE dùng nhiều lần được tính một lần; ép NOT MATERIALIZED có thể nhân đôi công việc.
- Hiểu mặc định trước khi thêm hint.

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
