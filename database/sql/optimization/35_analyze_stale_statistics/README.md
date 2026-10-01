# Lab 35 · Stale statistics and ANALYZE

## Objective

Thấy statistics **cũ** làm planner chọn plan sai, và `ANALYZE` sửa nó.

## Problem

Bảng lab `lab_stale`: 1 triệu đơn cũ (2023–2025) đã ANALYZE, rồi nạp thêm 400k đơn tháng 9/2026 mà
**không** ANALYZE (autovacuum tắt riêng trên bảng lab). Histogram của `created_at` vẫn dừng ở 2025.

## Baseline Query

Q1 — Recent orders: the histogram does not know they exist

```sql
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';
```

Q2 — The bad estimate drives the join strategy

```sql
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Aggregate  (cost=13.78..13.79 rows=1 width=40) (actual time=34.702..34.702 rows=1 loops=1)
   Buffers: shared hit=4430
   ->  Index Scan using ix_lab35_stale_created on lab_stale  (actual time=0.005..19.703 rows=400000 loops=1)
         Index Cond: (lab_stale.created_at >= '2026-09-15 00:00:00+00'::timestamp with time zone)
         Buffers: shared hit=4430
   Buffers: shared hit=4
 Planning Time: 0.037 ms
 Execution Time: 34.711 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
HashAggregate (u.status)
  └── Nested Loop                rows=362        actual rows=400000
        ├── Index Scan using ix_lab35_stale_created on lab_stale s   rows=362   actual 400000
        └── Index Scan using pk_users on users u                       loops=400000
```
`created_at >= '2026-09-15'` nằm ngoài bucket cuối của histogram → planner nghĩ chỉ ~362 dòng khớp →
Nested Loop một luồng với 400k lần tra `users`.

## Bottleneck

Ước lượng 362 vs thực tế 400,000 (sai ~1,100 lần) → plan một luồng, ~2 giây.

## Optimization Strategy A

**ANALYZE lab_stale** — file [`02_optimize.sql`](02_optimize.sql)

```sql
ANALYZE lab_stale;
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=10855.62..10855.63 rows=1 width=40) (actual time=17.066..19.826 rows=1 loops=1)
   Buffers: shared hit=5489
   ->  Gather  (cost=10855.39..10855.60 rows=2 width=40) (actual time=17.008..19.819 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=5489
         ->  Partial Aggregate  (cost=9855.39..9855.40 rows=1 width=40) (actual time=16.066..16.066 rows=1 loops=3)
               Buffers: shared hit=5489
               ->  Parallel Index Scan using ix_lab35_stale_created on lab_stale  (actual time=0.006..9.971 rows=133333 loops=3)
                     Index Cond: (lab_stale.created_at >= '2026-09-15 00:00:00+00'::timestamp with time zone)
                     Buffers: shared hit=5489
 Planning Time: 0.058 ms
 Execution Time: 19.839 ms
```

Ước lượng sát thực tế; plan song song, nhanh hơn ~3 lần.

## Why It Improved

Sau `ANALYZE lab_stale`: ước lượng ~490k (gần 400k) → planner chọn plan **song song** (Gather Merge,
3 process): ~0.7 s, nhanh hơn ~3 lần. Q1 cũng chuyển sang aggregate song song.

## Trade-offs

- Autovacuum tự ANALYZE khi `n_mod_since_analyze > 50 + 10% × reltuples` — với bảng lớn, 10% có thể là
  hàng triệu dòng: một đợt nạp "chỉ" 5% không kích hoạt nó. Sau bulk load / ETL hãy chạy ANALYZE ngay.
- Có thể hạ ngưỡng theo bảng: `ALTER TABLE … SET (autovacuum_analyze_scale_factor = 0.02)`.
- `pg_restore` không khôi phục statistics (xem `scripts/restore.sh` chạy `vacuumdb --analyze-only`).

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Recent orders: the histogram does not know they exist**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using ix_lab35_stale_created on public.lab_stale` | 1 | 0 | shared hit=4430 | 34.7 ms |
| Strategy A | `Partial Aggregate, Parallel Index Scan using ix_lab35_stale_created on public.lab_stale` | 1 | 0 | shared hit=5489 | 19.8 ms |

**Q2 — The bad estimate drives the join strategy**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Nested Loop, Index Scan using ix_lab35_stale_created on public.lab_stale s, Index Scan using pk_users on public.users u` | 4 | 0 | shared hit=1197859 read=406571 | 1,887.7 ms |
| Strategy A | `Sort, Partial HashAggregate, Nested Loop, Parallel Index Scan using ix_lab35_stale_created on public.lab_stale s, Index ` | 4 | 0 | shared hit=1198651 read=406884 written=29 | 700.0 ms |

## Reset

```sql
-- (strategy A has no object of its own: 05_reset.sql drops lab_stale)
DROP TABLE IF EXISTS lab_stale;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `rows=` rất nhỏ trên một node mà `actual rows` khổng lồ, nhất là với điều kiện trên dữ liệu **mới**.
- `pg_stat_user_tables.n_mod_since_analyze`, `last_analyze`, `last_autoanalyze`.
- `pg_class.reltuples` vs `count(*)`.

## Interview Questions

1. Khi nào autovacuum chạy ANALYZE?
2. Vì sao điều kiện trên giá trị mới nhất (created_at gần đây) hay bị ước lượng sai?
3. Nên làm gì sau một đợt bulk load?
4. Làm sao phát hiện statistics cũ trên production?

## Key Takeaways

- Statistics cũ = ước lượng sai = plan sai.
- Chạy ANALYZE sau bulk load, đừng chờ autovacuum.
- Dữ liệu tăng theo thời gian dễ bị lệch histogram ở 'đuôi' mới nhất.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
