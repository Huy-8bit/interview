# Lab 38 · Index bloat: pgstatindex and REINDEX

## Objective

Đo **index bloat** bằng `pgstatindex` và thu hồi bằng `REINDEX` / `REINDEX CONCURRENTLY`.

## Problem

Bảng lab `lab_index_bloat` (payments có `transaction_id` uuid ngẫu nhiên) bị xoá 80% dòng rồi VACUUM.
Entry trong index đã được dọn, nhưng các trang lá chỉ còn ~20% đầy: một range scan đọc nhiều trang gấp
nhiều lần cần thiết.

## Baseline Query

Q1 — Count a range of transaction ids through the index

```sql
SELECT count(*)
FROM lab_index_bloat
WHERE transaction_id >= '40000000-0000-0000-0000-000000000000'
  AND transaction_id <  '80000000-0000-0000-0000-000000000000';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Aggregate  (cost=2254.02..2254.03 rows=1 width=8) (actual time=2.994..2.994 rows=1 loops=1)
   Buffers: shared hit=961
   ->  Index Only Scan using ix_lab38_ibloat_txn on lab_index_bloat  (actual time=0.002..1.995 rows=50104 loops=1)
         Index Cond: ((lab_index_bloat.transaction_id >= '40000000-0000-0000-0000-000000000000'::uuid) AND (lab_index_bloat.transaction_id < ...
         Heap Fetches: 0
         Buffers: shared hit=961
 Planning Time: 0.010 ms
 Execution Time: 2.997 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

B-tree chỉ tái sử dụng / gỡ một trang khi nó **trống hoàn toàn**. Xoá ngẫu nhiên 80% để lại hầu hết các
trang còn vài entry — `avg_leaf_density` thấp. Index với khoá ngẫu nhiên (uuid v4) bị ảnh hưởng nặng nhất
vì entry bị xoá rải đều trên mọi trang.

```text
Aggregate
  └── Index Only Scan using ix_lab38_ibloat_txn     Buffers ≈ số trang lá trong khoảng
```

## Bottleneck

Range scan đọc ~960 trang index cho một khoảng mà index nén chặt chỉ cần ~200.

## Optimization Strategy A

**REINDEX INDEX: rebuild compactly** — file [`02_optimize.sql`](02_optimize.sql)

```sql
REINDEX INDEX ix_lab38_ibloat_txn;
```

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=1407.02..1407.03 rows=1 width=8) (actual time=2.906..2.906 rows=1 loops=1)
   Buffers: shared hit=196
   ->  Index Only Scan using ix_lab38_ibloat_txn on lab_index_bloat  (actual time=0.003..1.900 rows=50104 loops=1)
         Index Cond: ((lab_index_bloat.transaction_id >= '40000000-0000-0000-0000-000000000000'::uuid) AND (lab_index_bloat.transaction_id < ...
         Heap Fetches: 0
         Buffers: shared hit=196
 Planning Time: 0.009 ms
 Execution Time: 2.908 ms
```

Index nhỏ lại nhiều lần, `avg_leaf_density` ~90%; truy vấn đọc ~5 lần ít trang hơn.

## Why It Improved

`REINDEX INDEX` dựng lại index từ đầu với trang đầy (fillfactor 90): kích thước giảm mạnh, cùng truy vấn
đọc ~5 lần ít trang hơn.

## Trade-offs

- `REINDEX` thường: chặn ghi vào bảng (và các query dùng index đó) trong lúc chạy.
- `REINDEX CONCURRENTLY`: không chặn ghi, chậm hơn, tốn chỗ cho hai bản, không chạy trong transaction; thất
  bại để lại index `*_ccnew` INVALID phải drop (`00_environment/09_verify_baseline.sql` phát hiện được).
- UUID v7 / khoá tăng dần giảm loại bloat này (entry mới luôn ở cuối index).

## Optimization Strategy B

**REINDEX INDEX CONCURRENTLY: same result, no write lock** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
REINDEX INDEX CONCURRENTLY ix_lab38_ibloat_txn;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=1353.22..1353.23 rows=1 width=8) (actual time=3.330..3.331 rows=1 loops=1)
   Buffers: shared hit=196
   ->  Index Only Scan using ix_lab38_ibloat_txn on lab_index_bloat  (actual time=0.007..2.240 rows=50104 loops=1)
         Index Cond: ((lab_index_bloat.transaction_id >= '40000000-0000-0000-0000-000000000000'::uuid) AND (lab_index_bloat.transaction_id < ...
         Heap Fetches: 0
         Buffers: shared hit=196
 Planning Time: 0.040 ms
 Execution Time: 3.340 ms
```

`REINDEX CONCURRENTLY`: cùng kết quả, bảng vẫn ghi được trong lúc chạy.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Count a range of transaction ids through the index**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Only Scan using ix_lab38_ibloat_txn on public.lab_index_bloat` | 1 | 0 | shared hit=961 | 2.997 ms |
| Strategy A | `Index Only Scan using ix_lab38_ibloat_txn on public.lab_index_bloat` | 1 | 0 | shared hit=196 | 2.908 ms |
| Strategy B | `Index Only Scan using ix_lab38_ibloat_txn on public.lab_index_bloat` | 1 | 0 | shared hit=196 | 3.340 ms |

## Reset

```sql
-- (no object of its own: 05_reset.sql drops lab_index_bloat)
-- (no object of its own: 05_reset.sql drops lab_index_bloat)
DROP TABLE IF EXISTS lab_index_bloat;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `pgstatindex()`: `leaf_pages`, `avg_leaf_density`, `empty_pages`, `deleted_pages`.
- Buffers của Index (Only) Scan trước và sau REINDEX.

## Interview Questions

1. Index bloat là gì? Vì sao VACUUM không sửa được nó hoàn toàn?
2. Khoá ngẫu nhiên (uuid) ảnh hưởng gì đến B-tree?
3. REINDEX và REINDEX CONCURRENTLY khác nhau thế nào?
4. Làm sao theo dõi index bloat định kỳ?

## Key Takeaways

- VACUUM dọn entry chết nhưng không nén các trang index còn một phần.
- pgstatindex đo mật độ trang lá; REINDEX khôi phục nó.
- Trên production: REINDEX CONCURRENTLY.

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
