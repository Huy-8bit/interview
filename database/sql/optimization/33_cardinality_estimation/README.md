# Lab 33 · Cardinality estimation: correlated columns and CREATE STATISTICS

## Objective

Hiểu ước lượng cardinality khi các cột **tương quan**, và sửa bằng extended statistics `dependencies` / `mcv`.

## Problem

Đếm địa chỉ ở Hà Nội, Việt Nam (~155k). Planner nhân hai xác suất như thể độc lập:
`P(VN) × P(Hanoi)` — nhưng mọi địa chỉ Hanoi đều ở VN. Ước lượng ~10.5k, **thấp hơn ~15 lần**.
Q2 dùng con số đó làm phía ngoài của một join.

## Baseline Query

Q1 — Addresses in Hanoi, Vietnam (two correlated columns)

```sql
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';
```

Q2 — The estimate feeds a join: orders shipped to default addresses in Hanoi

```sql
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=185909.74..185909.75 rows=1 width=8) (actual time=335.908..340.082 rows=1 loops=1)
   Buffers: shared hit=320 read=134580
   ->  Gather  (cost=185909.52..185909.73 rows=2 width=8) (actual time=335.770..340.070 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=320 read=134580
         ->  Partial Aggregate  (cost=184909.52..184909.53 rows=1 width=8) (actual time=323.506..323.506 rows=1 loops=3)
               Buffers: shared hit=320 read=134580
               ->  Parallel Seq Scan on addresses  (cost=0.00..184900.80 rows=3489 width=0) (actual time=3.562..320.315 rows=51657 loops=3)
                     Filter: ((addresses.country_code = 'VN'::bpchar) AND ((addresses.city)::text = 'Hanoi'::text))
                     Rows Removed by Filter: 2614585
                     Buffers: shared hit=320 read=134580
 Planning Time: 0.053 ms
 Execution Time: 340.335 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Finalize Aggregate
  └── Gather → Partial Aggregate
        └── Parallel Seq Scan on addresses   rows=3489 (× 3 process ≈ 10.5k)   actual ≈ 51.6k × 3
              Filter: (country_code = 'VN' AND city = 'Hanoi')
```
Q2:
```text
Nested Loop   rows=1365 (×3)   actual ≈ 33k (×3)
  ├── Parallel Index Scan using ux_addresses_one_default_per_user   (default addresses in Hanoi)
  └── Index Scan using idx_orders_user_id   loops=98506
```

## Bottleneck

Ước lượng sai ~15 lần. Ở đây plan vẫn hợp lý (Nested Loop + index), nhưng trong một query phức tạp hơn,
"1,365 dòng" thay vì 99k có thể khiến planner chọn Nested Loop cho một join mà Hash Join tốt hơn nhiều.

## Optimization Strategy A

**CREATE STATISTICS (dependencies) ON country_code, city** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE STATISTICS st_lab33_addr_country_city (dependencies) ON country_code, city FROM addresses;
ANALYZE addresses;
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=185950.83..185950.84 rows=1 width=8) (actual time=195.934..199.038 rows=1 loops=1)
   Buffers: shared hit=16911 read=117989
   ->  Gather  (cost=185950.61..185950.82 rows=2 width=8) (actual time=195.853..199.029 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=16911 read=117989
         ->  Partial Aggregate  (cost=184950.61..184950.62 rows=1 width=8) (actual time=188.050..188.050 rows=1 loops=3)
               Buffers: shared hit=16911 read=117989
               ->  Parallel Seq Scan on addresses  (cost=0.00..184894.02 rows=22634 width=0) (actual time=2.148..186.734 rows=51657 loops=3)
                     Filter: ((addresses.country_code = 'VN'::bpchar) AND ((addresses.city)::text = 'Hanoi'::text))
                     Rows Removed by Filter: 2614585
                     Buffers: shared hit=16911 read=117989
 Planning Time: 0.082 ms
 Execution Time: 199.370 ms
```

Ước lượng Q1 tăng từ ~10.5k lên ~68k (thực tế 155k).

## Why It Improved

- `CREATE STATISTICS … (dependencies)`: lưu mức độ "city quyết định country" → planner không nhân hai
  selectivity: ước lượng Q1 ~68k (vẫn thấp ~2.3 lần — dependencies dùng tần suất trung bình của city).
- `CREATE STATISTICS … (mcv)`: lưu tần suất của từng **cặp** (country_code, city) phổ biến → ước lượng
  ~203k, gần thực tế nhất trong ba (cao hơn ~30%, sai số do lấy mẫu).
Plan không đổi trong lab này (Nested Loop vẫn là lựa chọn đúng), nhưng ước lượng cho các node phía trên chính xác hơn.

## Trade-offs

- Extended statistics chỉ được thu thập khi ANALYZE; tốn thêm thời gian ANALYZE và dung lượng catalog.
- Chỉ áp dụng cho các cột **cùng bảng** (không giúp tương quan qua join).
- `dependencies` chỉ cho điều kiện `=`; `mcv` xử lý thêm `IN`, `<`, `>` và các tổ hợp phổ biến.

## Optimization Strategy B

**CREATE STATISTICS (mcv) ON country_code, city** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE STATISTICS st_lab33_addr_country_city_mcv (mcv) ON country_code, city FROM addresses;
ANALYZE addresses;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize Aggregate  (cost=186065.70..186065.71 rows=1 width=8) (actual time=219.898..223.517 rows=1 loops=1)
   Buffers: shared hit=16880 read=118020
   ->  Gather  (cost=186065.48..186065.69 rows=2 width=8) (actual time=219.798..223.507 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=16880 read=118020
         ->  Partial Aggregate  (cost=185065.48..185065.49 rows=1 width=8) (actual time=210.649..210.649 rows=1 loops=3)
               Buffers: shared hit=16880 read=118020
               ->  Parallel Seq Scan on addresses  (cost=0.00..184896.05 rows=67772 width=0) (actual time=2.151..209.033 rows=51657 loops=3)
                     Filter: ((addresses.country_code = 'VN'::bpchar) AND ((addresses.city)::text = 'Hanoi'::text))
                     Rows Removed by Filter: 2614585
                     Buffers: shared hit=16880 read=118020
 Planning Time: 0.072 ms
 Execution Time: 223.792 ms
```

Ước lượng Q1 ~203k — sát thực tế nhất. Xem danh sách cặp MCV trong `02b_strategy_b.sql` (`pg_mcv_list_items`).

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Addresses in Hanoi, Vietnam (two correlated columns)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.addresses` | 1 | 2,614,585 | shared hit=320 read=134580 | 340.3 ms |
| Strategy A | `Partial Aggregate, Parallel Seq Scan on public.addresses` | 1 | 2,614,585 | shared hit=16911 read=117989 | 199.4 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.addresses` | 1 | 2,614,585 | shared hit=16880 read=118020 | 223.8 ms |

**Q2 — The estimate feeds a join: orders shipped to default addresses in Hanoi**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Nested Loop, Parallel Index Scan using ux_addresses_one_default_per_user on public.addresses a, Index` | 1 | 1,633,831 | shared hit=306504 read=250374 | 722.2 ms |
| Strategy A | `Partial Aggregate, Nested Loop, Parallel Index Scan using ux_addresses_one_default_per_user on public.addresses a, Index` | 1 | 1,633,831 | shared hit=306862 read=250374 | 630.6 ms |
| Strategy B | `Partial Aggregate, Nested Loop, Parallel Index Scan using ux_addresses_one_default_per_user on public.addresses a, Index` | 1 | 1,633,831 | shared hit=306812 read=250375 | 497.6 ms |

## Reset

```sql
DROP STATISTICS IF EXISTS st_lab33_addr_country_city;
DROP STATISTICS IF EXISTS st_lab33_addr_country_city_mcv;
ANALYZE addresses;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Với plan song song, `rows=` ở node dưới Gather là **mỗi process**: nhân với số process (`loops`) để so.
- So `rows=` với `actual rows × loops` trên node có điều kiện nhiều cột.
- `pg_stats_ext`: `dependencies`, `n_distinct`, `most_common_vals`.

## Interview Questions

1. Planner kết hợp selectivity của nhiều điều kiện như thế nào?
2. Extended statistics có những loại nào? Mỗi loại sửa vấn đề gì?
3. Vì sao ước lượng sai số dòng nguy hiểm cho Nested Loop?
4. Extended statistics có giúp tương quan giữa hai bảng trong join không?

## Key Takeaways

- Planner giả định các cột độc lập — dữ liệu thật hiếm khi như vậy (city → country, model → brand…).
- CREATE STATISTICS dạy planner về tương quan trong một bảng.
- Ước lượng tốt quan trọng nhất ở các node nằm dưới một join.

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
