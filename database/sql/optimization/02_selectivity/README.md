# Lab 02 · Selectivity: the same index, different plans

## Objective

Hiểu **selectivity** (tỉ lệ dòng khớp điều kiện) và vì sao *cùng một index, cùng một dạng query*
lại cho các plan khác nhau tùy **giá trị** được tìm.

## Problem

`payments.status` có 4 giá trị phân bố rất lệch: SUCCEEDED ~79%, PENDING ~8.5%, FAILED ~7.2%,
REFUNDED ~5%. Báo cáo tài chính cần tổng tiền theo từng trạng thái. Có nên tạo index trên
`status` không? Index đó được dùng khi nào?

## Baseline Query

Q1 — Very common value: SUCCEEDED (~79% of rows)

```sql
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED';
```

Q2 — Less common value: PENDING (~8.5%)

```sql
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'PENDING';
```

Q3 — Rare value: REFUNDED (~5%)

```sql
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'REFUNDED';
```

## Expected Plan

Plan quan sát được (BEFORE, cả 3 query đều là Seq Scan vì chưa có index). Với index của Strategy A,
planner dùng index cho PENDING và REFUNDED nhưng vẫn Seq Scan cho SUCCEEDED:

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=138012.14..138012.15 rows=1 width=40) (actual time=153.351..155.059 rows=1 loops=1)
   Buffers: shared hit=288 read=101560
   ->  Gather  (cost=138011.91..138012.12 rows=2 width=40) (actual time=153.272..155.051 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=288 read=101560
         ->  Partial Aggregate  (cost=137011.91..137011.92 rows=1 width=40) (actual time=147.127..147.127 rows=1 loops=3)
               Buffers: shared hit=288 read=101560
               ->  Parallel Seq Scan on payments  (actual time=1.999..96.069 rows=1355048 loops=3)
                     Filter: (payments.status = 'SUCCEEDED'::payment_status)
                     Rows Removed by Filter: 354557
                     Buffers: shared hit=288 read=101560
 Planning Time: 0.046 ms
 Execution Time: 155.261 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Planner không "thử" các plan; nó **ước lượng** chi phí từng plan bằng thống kê:

1. `pg_stats.most_common_vals / most_common_freqs` cho biết tần suất từng giá trị
   (ví dụ SUCCEEDED ≈ 0.79).
2. Số dòng ước lượng = tần suất × `reltuples` (5.1 triệu) → hiện ở `rows=` của node scan.
3. Chi phí Seq Scan ≈ `seq_page_cost × số trang + cpu_tuple_cost × số dòng`.
   Chi phí Index Scan ≈ trang index + `random_page_cost × số trang heap phải đọc` + CPU.
4. Plan rẻ nhất (theo ước lượng) thắng.

```text
Finalize Aggregate
  └── Gather (2 workers)
        └── Partial Aggregate          <- mỗi worker tính count/sum một phần
              └── Parallel Seq Scan     (SUCCEEDED)
                  hoặc Parallel Index Scan using ix_lab02_payments_status (PENDING, REFUNDED)
```

## Bottleneck

Với PENDING / REFUNDED, Seq Scan đọc toàn bộ ~102k trang để lấy 5–8% số dòng
(`Rows Removed by Filter` ≈ 1.6 triệu mỗi loop).

## Optimization Strategy A

**B-tree index on payments(status)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab02_payments_status ON payments (status);
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=138020.51..138020.52 rows=1 width=40) (actual time=157.872..159.558 rows=1 loops=1)
   Buffers: shared hit=1248 read=100600
   ->  Gather  (cost=138020.29..138020.50 rows=2 width=40) (actual time=157.797..159.549 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=1248 read=100600
         ->  Partial Aggregate  (cost=137020.29..137020.30 rows=1 width=40) (actual time=151.492..151.492 rows=1 loops=3)
               Buffers: shared hit=1248 read=100600
               ->  Parallel Seq Scan on payments  (actual time=1.968..99.619 rows=1355048 loops=3)
                     Filter: (payments.status = 'SUCCEEDED'::payment_status)
                     Rows Removed by Filter: 354557
                     Buffers: shared hit=1248 read=100600
 Planning Time: 0.062 ms
 Execution Time: 159.774 ms
```

SUCCEEDED vẫn Seq Scan; PENDING và REFUNDED dùng `Parallel Index Scan using ix_lab02_payments_status`.

## Why It Improved

Với **PENDING** (8.5%), Index Scan chỉ đọc ~53k trang thay vì 102k và nhanh hơn rõ rệt.
Nhưng hãy nhìn kỹ **REFUNDED** trong bảng so sánh: planner chọn index (ước lượng rẻ hơn) nhưng
thực tế vẫn chạm ~90k trang và **chậm hơn** Seq Scan. Lý do: các dòng REFUNDED nằm rải rác —
gần như trang heap nào cũng có vài dòng REFUNDED, nên "đọc ít dòng" không có nghĩa là "đọc ít
trang". Planner dùng `correlation` để ước lượng điều này nhưng mô hình không hoàn hảo.
Bài học: **ước lượng của planner có thể sai; luôn kiểm chứng bằng EXPLAIN (ANALYZE, BUFFERS)**.

## Trade-offs

- Index trên cột ít giá trị (low cardinality) thường lớn mà ít hữu ích: 34 MB, phần lớn là
  entry SUCCEEDED không bao giờ được dùng.
- Index Scan đọc heap theo thứ tự index (ngẫu nhiên); khi số trang phải đọc gần bằng toàn bảng,
  nó có thể chậm hơn Seq Scan (đọc tuần tự, có read-ahead).
- Kết quả phụ thuộc thống kê: sau khi phân bố dữ liệu thay đổi mà chưa `ANALYZE`, plan có thể sai.

## Optimization Strategy B

**Partial index: only the rows that are NOT 'SUCCEEDED'** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab02_payments_status_not_succeeded
    ON payments (status) WHERE status <> 'SUCCEEDED';
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize Aggregate  (cost=138020.51..138020.52 rows=1 width=40) (actual time=156.136..159.165 rows=1 loops=1)
   Buffers: shared hit=32412 read=69436
   ->  Gather  (cost=138020.29..138020.50 rows=2 width=40) (actual time=156.061..159.149 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=32412 read=69436
         ->  Partial Aggregate  (cost=137020.29..137020.30 rows=1 width=40) (actual time=149.829..149.829 rows=1 loops=3)
               Buffers: shared hit=32412 read=69436
               ->  Parallel Seq Scan on payments  (actual time=1.875..98.444 rows=1355048 loops=3)
                     Filter: (payments.status = 'SUCCEEDED'::payment_status)
                     Rows Removed by Filter: 354557
                     Buffers: shared hit=32412 read=69436
 Planning Time: 0.043 ms
 Execution Time: 159.359 ms
```

Partial index chỉ chứa các dòng `status <> 'SUCCEEDED'`: **7.2 MB thay vì 34 MB** (nhỏ ~5 lần), cho
đúng các plan như Strategy A vì điều kiện `status = 'PENDING'` suy ra được `status <> 'SUCCEEDED'`.
Mỗi INSERT một payment SUCCEEDED (79% số ghi) không phải cập nhật index này.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Very common value: SUCCEEDED (~79% of rows)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.payments` | 1 | 354,557 | shared hit=288 read=101560 | 155.3 ms |
| Strategy A | `Partial Aggregate, Parallel Seq Scan on public.payments` | 1 | 354,557 | shared hit=1248 read=100600 | 159.8 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.payments` | 1 | 354,557 | shared hit=32412 read=69436 | 159.4 ms |

**Q2 — Less common value: PENDING (~8.5%)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.payments` | 1 | 1,564,406 | shared hit=576 read=101272 | 93.5 ms |
| Strategy A | `Partial Aggregate, Parallel Index Scan using ix_lab02_payments_status on public.payments` | 1 | 0 | shared hit=380 read=52513 written=1 | 79.8 ms |
| Strategy B | `Partial Aggregate, Parallel Index Scan using ix_lab02_payments_status_not_succeeded on public.payments` | 1 | 0 | shared hit=467 read=52417 | 73.1 ms |

**Q3 — Rare value: REFUNDED (~5%)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.payments` | 1 | 1,623,754 | shared hit=864 read=100984 | 90.6 ms |
| Strategy A | `Partial Aggregate, Parallel Index Scan using ix_lab02_payments_status on public.payments` | 1 | 0 | shared hit=130 read=90403 written=1 | 113.4 ms |
| Strategy B | `Partial Aggregate, Parallel Index Scan using ix_lab02_payments_status_not_succeeded on public.payments` | 1 | 0 | shared hit=139 read=90403 | 118.5 ms |

Partial index thắng: cùng lợi ích đọc, nhỏ hơn 5 lần, ghi rẻ hơn.

## Reset

```sql
DROP INDEX IF EXISTS ix_lab02_payments_status;
DROP INDEX IF EXISTS ix_lab02_payments_status_not_succeeded;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `rows=` (ước lượng) trên node scan và so với `actual rows × loops`.
- Cùng query shape, plan khác nhau → nguyên nhân là **selectivity**, không phải cú pháp.
- `Buffers` của Index Scan: nếu gần bằng số trang của bảng, index không tiết kiệm được I/O.
- `pg_stats.correlation` của cột: gần 0 = dữ liệu rải rác → Index Scan phải nhảy khắp heap.

## Interview Questions

1. Selectivity và cardinality khác nhau thế nào?
2. Planner lấy tần suất của một giá trị từ đâu? Nếu giá trị không nằm trong MCV list thì sao?
3. Vì sao index trên cột boolean/status thường vô ích? Khi nào nó lại hữu ích?
4. Planner chọn Index Scan nhưng thực tế chậm hơn Seq Scan — có thể vì những lý do gì?
5. Partial index được dùng khi nào? Planner kiểm tra điều kiện đó ra sao?

## Key Takeaways

- Planner chọn plan theo số dòng ước lượng, mà số dòng phụ thuộc giá trị cụ thể trong WHERE.
- Ít dòng chưa chắc là ít trang: dữ liệu rải rác làm Index Scan đọc gần hết bảng.
- Với cột phân bố lệch, partial index chỉ cho các giá trị hiếm thường là lựa chọn tốt nhất.
- Luôn kiểm chứng bằng EXPLAIN (ANALYZE, BUFFERS) — ước lượng có thể sai.

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
