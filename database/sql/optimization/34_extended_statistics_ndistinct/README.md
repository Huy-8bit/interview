# Lab 34 · Extended statistics: ndistinct for multi-column GROUP BY

## Objective

Dùng extended statistics `ndistinct` để sửa ước lượng số nhóm của `GROUP BY` nhiều cột.

## Problem

`GROUP BY country_code, city` trên 8 triệu địa chỉ: thực tế 7,837 nhóm. Planner nhân số giá trị phân
biệt của từng cột → ước lượng 23,481 nhóm (cao gấp 3).

## Baseline Query

Q1 — Addresses per (country, city)

```sql
SELECT country_code, city, count(*)
FROM addresses
GROUP BY country_code, city;
```

Q2 — The group estimate feeds the next step: cities with more than 1,000 addresses

```sql
SELECT country_code, city, count(*) AS addresses
FROM addresses
GROUP BY country_code, city
HAVING count(*) > 1000
ORDER BY addresses DESC;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize HashAggregate  (cost=199509.03..199743.84 rows=23481 width=21) (actual time=575.260..576.372 rows=7837 loops=1)
   Group Key: addresses.country_code, addresses.city
   Batches: 1  Memory Usage: 1809kB
   Buffers: shared hit=16902 read=117998
   ->  Gather  (cost=194225.80..199156.81 rows=46962 width=21) (actual time=571.658..573.238 rows=14610 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=16902 read=117998
         ->  Partial HashAggregate  (cost=193225.80..193460.61 rows=23481 width=21) (actual time=552.951..553.337 rows=4870 loops=3)
               Group Key: addresses.country_code, addresses.city
               Batches: 1  Memory Usage: 1297kB
               Buffers: shared hit=16902 read=117998
               ->  Parallel Seq Scan on addresses  (actual time=0.024..162.433 rows=2666243 loops=3)
                     Buffers: shared hit=16902 read=117998
   Buffers: shared hit=5
 Planning Time: 0.260 ms
 Execution Time: 577.000 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Finalize HashAggregate  rows=23481   actual rows=7837
  └── Gather  rows=46962  actual ≈ 14.6k
        └── Partial HashAggregate
              └── Parallel Seq Scan on addresses
```
Q2 (HAVING count > 1000): ước lượng 7,827 nhóm còn lại, thực tế 262.

## Bottleneck

Ước lượng số nhóm sai ~3 lần (chiều cao hơn) → ước lượng bộ nhớ cho HashAggregate và số dòng cho các node phía trên sai theo.

## Optimization Strategy A

**CREATE STATISTICS (ndistinct) ON country_code, city** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE STATISTICS st_lab34_addr_ndistinct (ndistinct) ON country_code, city FROM addresses;
ANALYZE addresses;
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize GroupAggregate  (cost=194404.92..195101.68 rows=2697 width=21) (actual time=568.510..575.006 rows=7837 loops=1)
   Group Key: addresses.country_code, addresses.city
   Buffers: shared hit=17444 read=117486
   ->  Gather Merge  (cost=194404.92..195034.26 rows=5394 width=21) (actual time=568.501..573.662 rows=14614 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=17444 read=117486
         ->  Sort  (cost=193404.89..193411.63 rows=2697 width=21) (actual time=554.263..554.393 rows=4871 loops=3)
               Sort Key: addresses.country_code, addresses.city
               Sort Method: quicksort  Memory: 436kB
               Buffers: shared hit=17444 read=117486
               ->  Partial HashAggregate  (cost=193224.23..193251.20 rows=2697 width=21) (actual time=549.511..549.790 rows=4871 loops=3)
                     Group Key: addresses.country_code, addresses.city
                     Batches: 1  Memory Usage: 721kB
                     Buffers: shared hit=17414 read=117486
                     ->  Parallel Seq Scan on addresses  (actual time=0.038..158.800 rows=2666243 loops=3)
                           Buffers: shared hit=17414 read=117486
   Buffers: shared hit=5
 Planning Time: 0.234 ms
 Execution Time: 575.452 ms
```

`(ndistinct)`: ước lượng 2,697 nhóm (thực tế 7,837); plan chuyển sang GroupAggregate.

## Why It Improved

Quan sát thật, và không hoàn toàn như kỳ vọng: với `ndistinct`, ước lượng thành **2,697** nhóm — giờ
**thấp** hơn thực tế ~3 lần (thay vì cao hơn 3 lần). `ndistinct` đa cột cũng được đo trên mẫu 30k dòng
của ANALYZE, mà dữ liệu có hàng nghìn thị trấn nhỏ chỉ vài địa chỉ — mẫu bỏ sót chúng. Plan đổi từ
HashAggregate sang Sort + GroupAggregate, thời gian tương đương.

## Trade-offs

- Extended statistics cải thiện mô hình (không nhân mù quáng) nhưng vẫn bị giới hạn bởi kích thước mẫu.
- Kết hợp với `ALTER TABLE … ALTER COLUMN … SET STATISTICS` lớn hơn để tăng mẫu của ANALYZE nếu cần.

## Optimization Strategy B

**All kinds at once: (ndistinct, dependencies, mcv) on country_code, state, city** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE STATISTICS st_lab34_addr_all (ndistinct, dependencies, mcv) ON country_code, state, city FROM addresses;
ANALYZE addresses;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize GroupAggregate  (cost=194406.41..195112.48 rows=2733 width=21) (actual time=613.259..620.631 rows=7837 loops=1)
   Group Key: addresses.country_code, addresses.city
   Buffers: shared hit=17988 read=116942
   ->  Gather Merge  (cost=194406.41..195044.15 rows=5466 width=21) (actual time=613.251..619.438 rows=14617 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=17988 read=116942
         ->  Sort  (cost=193406.39..193413.22 rows=2733 width=21) (actual time=600.205..600.329 rows=4872 loops=3)
               Sort Key: addresses.country_code, addresses.city
               Sort Method: quicksort  Memory: 436kB
               Buffers: shared hit=17988 read=116942
               ->  Partial HashAggregate  (cost=193223.05..193250.38 rows=2733 width=21) (actual time=595.420..595.685 rows=4872 loops=3)
                     Group Key: addresses.country_code, addresses.city
                     Batches: 1  Memory Usage: 721kB
                     Buffers: shared hit=17958 read=116942
                     ->  Parallel Seq Scan on addresses  (actual time=0.023..170.342 rows=2666243 loops=3)
                           Buffers: shared hit=17958 read=116942
   Buffers: shared hit=5
 Planning Time: 0.232 ms
 Execution Time: 621.067 ms
```

`(ndistinct, dependencies, mcv)` trên 3 cột: ước lượng tương tự (~2,733); xem `pg_stats_ext` trong file strategy.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Addresses per (country, city)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial HashAggregate, Parallel Seq Scan on public.addresses` | 7837 | 0 | shared hit=16902 read=117998 | 577.0 ms |
| Strategy A | `Sort, Partial HashAggregate, Parallel Seq Scan on public.addresses` | 7837 | 0 | shared hit=17444 read=117486 | 575.5 ms |
| Strategy B | `Sort, Partial HashAggregate, Parallel Seq Scan on public.addresses` | 7837 | 0 | shared hit=17988 read=116942 | 621.1 ms |

**Q2 — The group estimate feeds the next step: cities with more than 1,000 addresses**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Finalize HashAggregate, Partial HashAggregate, Parallel Seq Scan on public.addresses` | 262 | 7,575 | shared hit=17190 read=117710 | 512.5 ms |
| Strategy A | `Finalize GroupAggregate, Sort, Partial HashAggregate, Parallel Seq Scan on public.addresses` | 262 | 7,575 | shared hit=17732 read=117198 | 534.3 ms |
| Strategy B | `Finalize GroupAggregate, Sort, Partial HashAggregate, Parallel Seq Scan on public.addresses` | 262 | 7,575 | shared hit=18276 read=116654 | 504.3 ms |

## Reset

```sql
DROP STATISTICS IF EXISTS st_lab34_addr_ndistinct;
DROP STATISTICS IF EXISTS st_lab34_addr_all;
ANALYZE addresses;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `rows=` của node Aggregate vs `actual rows`.
- Plan đổi loại aggregate khi ước lượng đổi.

## Interview Questions

1. Planner ước lượng số nhóm của GROUP BY a, b thế nào khi không có extended statistics?
2. ndistinct statistics lưu gì?
3. Vì sao extended statistics vẫn có thể ước lượng sai?

## Key Takeaways

- GROUP BY nhiều cột tương quan: planner thường ước lượng quá cao số nhóm.
- ndistinct sửa mô hình, nhưng độ chính xác vẫn phụ thuộc mẫu của ANALYZE.
- Đo trước và sau — đừng giả định statistics mới luôn tốt hơn.

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
