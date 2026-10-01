# Lab 28 · EXISTS vs IN, NOT EXISTS vs NOT IN (and the NULL trap)

## Objective

So sánh `IN` / `EXISTS` và `NOT IN` / `NOT EXISTS`: plan, hiệu năng, và bẫy NULL của `NOT IN`.

## Problem

Khách đặt hàng trong ngày cuối; khách đăng ký gần đây nhưng chưa từng đặt hàng.

## Baseline Query

Q1 — IN: customers who ordered on the last day

```sql
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-30');
```

Q2 — EXISTS: the same question

```sql
SELECT count(*)
FROM users u
WHERE EXISTS (SELECT 1 FROM orders o
              WHERE o.user_id = u.id AND o.created_at >= '2026-09-30');
```

Q3 — NOT EXISTS: recent sign-ups who never ordered

```sql
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

Q4 — NOT IN: the same question - EXPLAIN ONLY

```sql
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o);
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=73686.90..73686.91 rows=1 width=8) (actual time=150.484..154.387 rows=1 loops=1)
   Buffers: shared hit=18219
   ->  Gather  (cost=73686.69..73686.90 rows=2 width=8) (actual time=150.317..154.383 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=18219
         ->  Partial Aggregate  (cost=72686.69..72686.70 rows=1 width=8) (actual time=149.382..149.383 rows=1 loops=3)
               Buffers: shared hit=18219
               ->  Parallel Hash Semi Join  (cost=5704.80..72587.51 rows=39670 width=0) (actual time=8.307..148.727 rows=29166 loops=3)
                     Hash Cond: (u.id = o.user_id)
                     Buffers: shared hit=18219
                     ->  Parallel Index Only Scan using pk_users on users u  (actual time=0.019..62.348 rows=1666667 loops=3)
                           Heap Fetches: 0
                           Buffers: shared hit=13777
                     ->  Parallel Hash  (cost=5208.49..5208.49 rows=39670 width=8) (actual time=8.089..8.090 rows=32193 loops=3)
                           Buckets: 131072  Batches: 1  Memory Usage: 4864kB
                           Buffers: shared hit=4376
                           ->  Parallel Index Scan using idx_orders_created_at on orders o  (actual time=0.020..6.098 rows=32193 loops=3)
                                 Index Cond: (o.created_at >= '2026-09-30 00:00:00+00'::timestamp with time zone)
                                 Buffers: shared hit=4376
   Buffers: shared hit=20
 Planning Time: 0.171 ms
 Execution Time: 154.403 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

IN và EXISTS (Q1, Q2) cho **cùng một plan**: `Parallel Hash Semi Join`.

NOT EXISTS (Q3):
```text
Nested Loop Anti Join
  ├── Parallel Seq Scan on users   (đăng ký từ 2026-09-25: ~35k)
  └── Index Only Scan using idx_orders_user_id   loops=35165   <- dừng ở dòng khớp đầu tiên
```

NOT IN (Q4) — **chỉ EXPLAIN**:
```text
Parallel Seq Scan on users
  Filter: (created_at >= ...) AND (NOT (SubPlan 1))
  SubPlan 1
    -> Materialize  (rows=5000010)
         -> Index Only Scan using idx_orders_user_id on orders
```
5 triệu user_id không vừa work_mem dưới dạng bảng băm → planner dùng **plain SubPlan**: với mỗi user,
quét lại danh sách 5 triệu id đã materialize → O(35k × 5M). Chạy query này có thể mất hàng giờ.

## Bottleneck

NOT IN với subquery lớn: SubPlan không băm, độ phức tạp nhân.

## Optimization Strategy A

**(experiment) NOT IN when it works - and the NULL trap** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=299683.11..299683.12 rows=1 width=8) (actual time=368.264..374.321 rows=1 loops=1)
   Buffers: shared hit=35216 read=249051
   ->  Gather  (cost=299682.89..299683.10 rows=2 width=8) (actual time=367.580..374.304 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=35216 read=249051
         ->  Partial Aggregate  (cost=298682.89..298682.90 rows=1 width=8) (actual time=358.910..358.911 rows=1 loops=3)
               Buffers: shared hit=35216 read=249051
               ->  Parallel Seq Scan on users u  (actual time=133.369..358.670 rows=7407 loops=3)
                     Filter: ((u.created_at >= '2026-09-25 00:00:00+00'::timestamp with time zone) AND (NOT (hashed SubPlan 1)))
                     Rows Removed by Filter: 1659260
                     Buffers: shared hit=35216 read=249051
                     SubPlan 1
                       ->  Index Scan using idx_orders_created_at on orders o  (actual time=0.128..49.268 rows=265473 loops=3)
                             Index Cond: (o.created_at >= '2026-09-28 00:00:00+00'::timestamp with time zone)
                             Buffers: shared hit=34067
 Planning Time: 0.346 ms
 Execution Time: 374.742 ms
```

NOT IN tập nhỏ: `NOT (hashed SubPlan 1)`. Thêm một NULL vào subquery: count = 0.

## Why It Improved

NOT EXISTS luôn được chuyển thành **Anti Join** (Hash / Nested Loop / Merge tùy dữ liệu) và có ngữ nghĩa
đúng với NULL. Trên lab: ~200 ms cho câu hỏi mà NOT IN không thể chạy xong trong thời gian hợp lý.

## Trade-offs

- NOT IN với tập nhỏ (Strategy A, Q1): `hashed SubPlan`, chạy được (nhưng vẫn chậm hơn NOT EXISTS trên lab).
- **Bẫy NULL**: `x NOT IN (…, NULL)` không bao giờ TRUE → Strategy A Q2 trả **0** thay vì 22,221.
  Cột trong subquery chỉ cần nullable (dù hiện chưa có NULL) là query đã mong manh.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — IN: customers who ordered on the last day**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Hash Semi Join, Parallel Index Only Scan using pk_users on public.users u, Parallel Index Sc` | 1 | 0 | shared hit=18219 | 154.4 ms |

**Q2 — EXISTS: the same question**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Hash Semi Join, Parallel Index Only Scan using pk_users on public.users u, Parallel Index Sc` | 1 | 0 | shared hit=18218 | 144.9 ms |

**Q3 — NOT EXISTS: recent sign-ups who never ordered**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Nested Loop Anti Join, Parallel Seq Scan on public.users u, Index Only Scan using idx_orders_user_id ` | 1 | 1,654,945 | shared hit=109122 read=249339 | 215.2 ms |

**Strategy A — (experiment) NOT IN when it works - and the NULL trap**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| NOT IN against a small set (hashed SubPlan) | `Partial Aggregate, Parallel Seq Scan on public.users u, Index Scan using idx_orders_created_at on public.orders o` | 1 | 1,659,260 | shared hit=35216 read=249051 | 374.7 ms |
| The NULL trap: one NULL in the subquery -> 0 rows | `Partial Aggregate, Parallel Seq Scan on public.users u, Append, Index Scan using idx_orders_created_at on public.orders ` | 1 | 1,666,667 | shared hit=35504 read=248763 | 351.5 ms |

## Reset

```sql
-- (nothing to undo: queries only)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Semi Join` / `Anti Join`: đã chuyển thành join (tốt).
- `NOT (SubPlan N)` không có chữ `hashed` + `Materialize`: nguy hiểm.
- Luôn `EXPLAIN` (không ANALYZE) trước khi chạy một query nghi ngờ.

## Interview Questions

1. IN và EXISTS khác nhau về hiệu năng không?
2. Vì sao NOT IN nguy hiểm khi subquery trả về NULL?
3. Hashed SubPlan và plain SubPlan khác nhau thế nào?
4. Vì sao nên dùng NOT EXISTS thay cho NOT IN?

## Key Takeaways

- IN ≈ EXISTS (semi join).
- Luôn dùng NOT EXISTS, không dùng NOT IN (subquery).
- EXPLAIN không chạy query: dùng nó để kiểm tra trước những query có thể chạy rất lâu.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
