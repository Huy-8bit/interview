# Lab 37 · Table bloat: VACUUM FULL vs CLUSTER

## Objective

Hiểu **table bloat**: không gian trống sau DELETE, và so sánh hai cách thu hồi: `VACUUM FULL` và `CLUSTER`.

## Problem

Bảng lab `lab_bloat` (1 triệu đơn, có cột jsonb `shipping_address`) bị xoá 70% dòng rồi VACUUM: file vẫn
~261 MB với ~69% không gian trống. Mỗi Seq Scan vẫn đọc toàn bộ file.

## Baseline Query

Q1 — Full scan of the 30% remaining rows

```sql
SELECT count(*), sum(total_amount)
FROM lab_bloat;
```

Q2 — All orders of a range of users (rows scattered over the table)

```sql
SELECT user_id, count(*), sum(total_amount)
FROM lab_bloat
WHERE user_id BETWEEN 1000000 AND 1100000
GROUP BY user_id;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=36219.15..36219.16 rows=1 width=40) (actual time=22.542..24.642 rows=1 loops=1)
   Buffers: shared hit=32547 read=797 written=28
   ->  Gather  (cost=36218.92..36219.13 rows=2 width=40) (actual time=22.449..24.633 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=32547 read=797 written=28
         ->  Partial Aggregate  (cost=35218.92..35218.93 rows=1 width=40) (actual time=21.533..21.533 rows=1 loops=3)
               Buffers: shared hit=32547 read=797 written=28
               ->  Parallel Seq Scan on lab_bloat  (cost=0.00..34593.95 rows=124995 width=6) (actual time=0.032..9.831 rows=100000 loops=3)
                     Buffers: shared hit=32547 read=797 written=28
 Planning Time: 0.029 ms
 Execution Time: 24.654 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Sau DELETE + VACUUM, các trang chứa ~30% dữ liệu sống rải đều trên toàn file. PostgreSQL chỉ cắt được
các trang **trống hoàn toàn ở cuối file**; trang ở giữa dù gần trống vẫn giữ.

```text
Finalize Aggregate
  └── Gather → Partial Aggregate
        └── Parallel Seq Scan on lab_bloat    Buffers ≈ toàn bộ ~33k trang cho 300k dòng
```

## Bottleneck

Seq Scan đọc ~33k trang trong khi dữ liệu sống chỉ cần ~10k.

## Optimization Strategy A

**VACUUM FULL: compact rewrite** — file [`02_optimize.sql`](02_optimize.sql)

```sql
VACUUM (FULL, ANALYZE) lab_bloat;
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=12875.23..12875.24 rows=1 width=40) (actual time=12.798..14.079 rows=1 loops=1)
   Buffers: shared hit=448 read=9552
   ->  Gather  (cost=12875.00..12875.21 rows=2 width=40) (actual time=12.727..14.072 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=448 read=9552
         ->  Partial Aggregate  (cost=11875.00..11875.01 rows=1 width=40) (actual time=11.804..11.805 rows=1 loops=3)
               Buffers: shared hit=448 read=9552
               ->  Parallel Seq Scan on lab_bloat  (cost=0.00..11250.00 rows=125000 width=6) (actual time=0.011..7.734 rows=100000 loops=3)
                     Buffers: shared hit=448 read=9552
 Planning Time: 0.055 ms
 Execution Time: 14.093 ms
```

`VACUUM FULL`: 261 MB → 78 MB; Seq Scan đọc ít trang hơn ~3 lần.

## Why It Improved

`VACUUM FULL` viết lại bảng chỉ với dòng sống: ~78 MB, Seq Scan đọc ~10k trang (Buffers giảm ~3 lần).
`CLUSTER … USING ix_lab37_bloat_user` cũng thu nhỏ y như vậy **và** sắp xếp vật lý theo `user_id`:
Q2 (đơn của một dải user) đọc ít trang hơn hẳn vì các dòng liên quan nằm cạnh nhau (correlation → ~1).

## Trade-offs

- Cả hai đều lock `ACCESS EXCLUSIVE` và cần chỗ cho bản sao.
- Thứ tự của CLUSTER **không được duy trì** cho dữ liệu ghi sau đó — phải CLUSTER lại định kỳ.
- `fillfactor < 100` chừa chỗ trong mỗi trang cho UPDATE (tăng HOT update, giảm bloat do update)
  đổi lại bảng lớn hơn.

## Optimization Strategy B

**CLUSTER ... USING ix_lab37_bloat_user: compact AND physically ordered by user_id** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CLUSTER lab_bloat USING ix_lab37_bloat_user;
ANALYZE lab_bloat;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize Aggregate  (cost=12875.23..12875.24 rows=1 width=40) (actual time=11.411..12.572 rows=1 loops=1)
   Buffers: shared hit=448 read=9552
   ->  Gather  (cost=12875.00..12875.21 rows=2 width=40) (actual time=11.297..12.566 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=448 read=9552
         ->  Partial Aggregate  (cost=11875.00..11875.01 rows=1 width=40) (actual time=10.469..10.470 rows=1 loops=3)
               Buffers: shared hit=448 read=9552
               ->  Parallel Seq Scan on lab_bloat  (cost=0.00..11250.00 rows=125000 width=6) (actual time=0.008..6.651 rows=100000 loops=3)
                     Buffers: shared hit=448 read=9552
 Planning Time: 0.045 ms
 Execution Time: 12.585 ms
```

`CLUSTER`: 78 MB và correlation của user_id ≈ 1 → Q2 đọc ít trang và nhanh hơn VACUUM FULL.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Full scan of the 30% remaining rows**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.lab_bloat` | 1 | 0 | shared hit=32547 read=797 written=28 | 24.7 ms |
| Strategy A | `Partial Aggregate, Parallel Seq Scan on public.lab_bloat` | 1 | 0 | shared hit=448 read=9552 | 14.1 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.lab_bloat` | 1 | 0 | shared hit=448 read=9552 | 12.6 ms |

**Q2 — All orders of a range of users (rows scattered over the table)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using ix_lab37_bloat_user on public.lab_bloat` | 10229 | 0 | shared hit=11880 | 6.658 ms |
| Strategy A | `Index Scan using ix_lab37_bloat_user on public.lab_bloat` | 10229 | 0 | shared hit=11816 | 9.589 ms |
| Strategy B | `Index Scan using ix_lab37_bloat_user on public.lab_bloat` | 10229 | 0 | shared hit=427 | 2.716 ms |

## Reset

```sql
-- (no object of its own: 05_reset.sql drops lab_bloat)
-- (no object of its own: 05_reset.sql drops lab_bloat)
DROP TABLE IF EXISTS lab_bloat;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `pgstattuple`: `tuple_percent` (dữ liệu sống), `free_percent`, `table_len`.
- Buffers của Seq Scan so với số dòng trả về.
- `pg_stats.correlation` sau CLUSTER.

## Interview Questions

1. Table bloat là gì? Nguyên nhân?
2. Vì sao VACUUM không thu nhỏ file?
3. CLUSTER khác VACUUM FULL ở điểm nào?
4. Làm sao thu hồi bloat mà không khoá bảng lâu trên production?

## Key Takeaways

- DELETE/UPDATE hàng loạt để lại không gian trống mà Seq Scan vẫn phải đọc.
- VACUUM FULL / CLUSTER thu hồi không gian bằng cách viết lại bảng (khoá hoàn toàn).
- CLUSTER còn cải thiện locality cho các truy vấn theo khoá được chọn — nhưng chỉ một lần.

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
