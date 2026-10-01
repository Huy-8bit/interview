# Lab 32 · Planner statistics: n_distinct, MCV, histogram, correlation

## Objective

Đọc `pg_stats` (`n_distinct`, `most_common_vals/freqs`, `histogram_bounds`, `correlation`, `null_frac`),
hiểu planner biến chúng thành số dòng ước lượng như thế nào, và sửa một ước lượng sai.

## Problem

`orders.user_id` có 2.22 triệu giá trị phân biệt trong 5 triệu dòng, phân bố lệch (20% khách tạo ~65%
đơn). ANALYZE chỉ lấy mẫu 30,000 dòng (300 × `default_statistics_target`) và ngoại suy `n_distinct` —
planner nghĩ có ~1.4 triệu khách.

## Baseline Query

Q1 — GROUP BY user_id: how many groups does the planner expect?

```sql
SELECT user_id, count(*)
FROM orders
GROUP BY user_id;
```

Q2 — Equality on one user_id: selectivity of a value NOT in the MCV list

```sql
SELECT count(*)
FROM orders
WHERE user_id = 2215979;
```

Q3 — Range on total_amount: estimated from the histogram

```sql
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 GroupAggregate  (cost=0.43..124682.63 rows=1392726 width=16) (actual time=1.063..637.383 rows=2219487 loops=1)
   Group Key: orders.user_id
   Buffers: shared hit=3437205
   ->  Index Only Scan using idx_orders_user_id on orders  (actual time=0.010..346.136 rows=5000000 loops=1)
         Heap Fetches: 0
         Buffers: shared hit=3437205
 Planning Time: 0.062 ms
 Execution Time: 675.841 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

- **null_frac**: tỉ lệ NULL.
- **n_distinct**: > 0 là số giá trị phân biệt; < 0 là `-(số phân biệt / số dòng)` (tự co giãn theo bảng).
  `-0.29` nghĩa là "29% số dòng" ≈ 1.46 triệu.
- **most_common_vals / most_common_freqs** (MCV): các giá trị phổ biến nhất và tần suất. `user_id`
  không có MCV (không giá trị nào đủ phổ biến trong mẫu).
- **histogram_bounds**: ranh giới các bucket có số dòng bằng nhau cho các giá trị *ngoài* MCV — dùng
  cho điều kiện khoảng (Q3).
- **correlation**: thứ tự vật lý so với thứ tự giá trị (1/-1 = đã sắp trên đĩa; 0 = ngẫu nhiên);
  ảnh hưởng chi phí Index Scan.

Ước lượng cho `user_id = X` (X không trong MCV):
`rows ≈ (1 − Σ MCV freqs − null_frac) / (n_distinct − số MCV) × reltuples` → ~3–4 dòng.
`GROUP BY user_id` dự kiến đúng `n_distinct` nhóm.

## Bottleneck

Không có vấn đề tốc độ ở đây — mà là **ước lượng sai**: 1.39 triệu nhóm dự kiến vs 2.22 triệu thực tế.
Ở query lớn hơn, con số này quyết định bộ nhớ cho HashAggregate, việc chọn Hash vs Group aggregate, và
số dòng đưa vào các join phía trên.

## Optimization Strategy A

**Bigger sample for one column: SET STATISTICS 1000 + ANALYZE** — file [`02_optimize.sql`](02_optimize.sql)

```sql
ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS 1000;
ANALYZE orders;
```

## Result

AFTER Strategy A — Q1:

```text
 GroupAggregate  (cost=0.43..125373.02 rows=1461679 width=16) (actual time=1.317..774.084 rows=2219487 loops=1)
   Group Key: orders.user_id
   Buffers: shared hit=3437205
   ->  Index Only Scan using idx_orders_user_id on orders  (actual time=0.009..449.310 rows=5000000 loops=1)
         Heap Fetches: 0
         Buffers: shared hit=3437205
 Planning Time: 0.109 ms
 Execution Time: 817.562 ms
```

`n_distinct` −0.29 (≈1.46M); GroupAggregate ước lượng ~1.46M nhóm — cải thiện rất ít.

## Why It Improved

Quan sát thật: Strategy A (`SET STATISTICS 1000` → mẫu 300,000 dòng, 1,001 bucket histogram) chỉ đẩy
ước lượng từ ~1.39 lên ~1.46 triệu — **vẫn sai ~35%**. Bộ ước lượng `n_distinct` từ mẫu nổi tiếng là
đánh giá thấp cột có nhiều giá trị hiếm, và mẫu lớn hơn 10 lần không sửa được bản chất đó.

Strategy B (`ALTER COLUMN user_id SET (n_distinct = -0.444)`) ghim tỉ lệ đã biết: ước lượng nhóm
**2,220,058** vs thực tế 2,219,487.

## Trade-offs

- `SET STATISTICS` lớn: ANALYZE chậm hơn, `pg_statistic` to hơn, planning chậm hơn một chút (histogram dài hơn).
- `n_distinct` thủ công là một **giả định cố định**: phải cập nhật nếu phân bố dữ liệu thay đổi.
  Dùng số âm (tỉ lệ) để nó tự co giãn theo kích thước bảng.
- Q2 (khách cụ thể có 16 đơn) vẫn ước lượng 2–4 dòng: ước lượng là *trung bình*, không phải cho
  từng giá trị ngoài MCV.

## Optimization Strategy B

**Override n_distinct manually: ALTER COLUMN ... SET (n_distinct = ...)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
ALTER TABLE orders ALTER COLUMN user_id SET (n_distinct = -0.444);
ANALYZE orders;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 GroupAggregate  (cost=0.43..132959.41 rows=2220058 width=16) (actual time=1.356..606.471 rows=2219487 loops=1)
   Group Key: orders.user_id
   Buffers: shared hit=3437205
   ->  Index Only Scan using idx_orders_user_id on orders  (actual time=0.012..328.823 rows=5000000 loops=1)
         Heap Fetches: 0
         Buffers: shared hit=3437205
 Planning Time: 0.123 ms
 Execution Time: 641.416 ms
```

`n_distinct = -0.444` (attoptions); GroupAggregate ước lượng 2,220,058 nhóm — gần như chính xác.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — GROUP BY user_id: how many groups does the planner expect?**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Only Scan using idx_orders_user_id on public.orders` | 2219487 | 0 | shared hit=3437205 | 675.8 ms |
| Strategy A | `Index Only Scan using idx_orders_user_id on public.orders` | 2219487 | 0 | shared hit=3437205 | 817.6 ms |
| Strategy B | `Index Only Scan using idx_orders_user_id on public.orders` | 2219487 | 0 | shared hit=3437205 | 641.4 ms |

**Q2 — Equality on one user_id: selectivity of a value NOT in the MCV list**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Only Scan using idx_orders_user_id on public.orders` | 1 | 0 | shared hit=8 | 0.005 ms |
| Strategy A | `Index Only Scan using idx_orders_user_id on public.orders` | 1 | 0 | shared hit=8 | 0.007 ms |
| Strategy B | `Index Only Scan using idx_orders_user_id on public.orders` | 1 | 0 | shared hit=8 | 0.007 ms |

**Q3 — Range on total_amount: estimated from the histogram**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.orders` | 1 | 1,644,997 | shared hit=18028 read=181966 | 202.8 ms |
| Strategy A | `Partial Aggregate, Parallel Seq Scan on public.orders` | 1 | 1,644,997 | shared hit=18348 read=181646 | 190.4 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.orders` | 1 | 1,644,997 | shared hit=18700 read=181294 | 192.2 ms |

## Reset

```sql
ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS -1;
ALTER TABLE orders ALTER COLUMN user_id RESET (n_distinct);
ANALYZE orders;   -- rebuild the statistics with the default settings
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- So `rows=` (ước lượng) với `actual rows` ở node aggregate / scan.
- `pg_stats` trước và sau ANALYZE; `pg_attribute.attstattarget`, `attoptions`.

## Interview Questions

1. pg_stats chứa những gì? Planner dùng chúng ra sao?
2. n_distinct âm nghĩa là gì?
3. Khi nào tăng statistics target? Chi phí là gì?
4. Vì sao n_distinct ước lượng từ mẫu thường thấp hơn thực tế?
5. Làm sao ước lượng số dòng cho `col = X` khi X không có trong MCV?

## Key Takeaways

- Mọi quyết định của planner bắt đầu từ số dòng ước lượng — và số đó đến từ pg_stats.
- Mẫu lớn hơn không luôn sửa được ước lượng sai; đo trước khi tăng statistics target.
- Khi biết chắc tỉ lệ phân biệt, ghim n_distinct (dạng tỉ lệ âm).

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
