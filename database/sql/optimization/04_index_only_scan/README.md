# Lab 04 · Index Only Scan, visibility map, Heap Fetches

## Objective

Hiểu **Index Only Scan**: vì sao nó vẫn có thể đọc heap (`Heap Fetches`), vai trò của
**visibility map** và **VACUUM**, và cách dùng `INCLUDE` để biến một query thành index-only.

## Problem

Thống kê số đơn và doanh thu theo khoảng thời gian. Bảng lab `lab_ios` (1 triệu đơn, copy từ
`orders`) vừa được tạo, chưa từng được VACUUM — giống một bảng vừa nạp dữ liệu lớn.

## Baseline Query

Q1 — Count orders in a date range: every needed column is in the index

```sql
SELECT count(*)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';
```

Q2 — Same range, but also reads total_amount (NOT in the index)

```sql
SELECT sum(total_amount)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';
```

## Expected Plan

Plan quan sát được (BEFORE): Q1 đã là Index Only Scan nhưng **Heap Fetches = 188,534 = mọi dòng**;
Q2 là Index Scan thường vì cần `total_amount`:

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=6049.86..6049.87 rows=1 width=8) (actual time=9.035..10.662 rows=1 loops=1)
   Buffers: shared hit=2541
   ->  Gather  (cost=6049.65..6049.86 rows=2 width=8) (actual time=9.015..10.656 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=2541
         ->  Partial Aggregate  (cost=5049.65..5049.66 rows=1 width=8) (actual time=8.105..8.105 rows=1 loops=3)
               Buffers: shared hit=2541
               ->  Parallel Index Only Scan using ix_lab04_ios_created on lab_ios  (actual time=0.010..6.414 rows=62845 loops=3)
                     Index Cond: ((lab_ios.created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone) AND (lab_ios.created_at < '2025 ...
                     Heap Fetches: 188534
                     Buffers: shared hit=2541
 Planning Time: 0.051 ms
 Execution Time: 10.675 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Finalize Aggregate
  └── Gather
        └── Partial Aggregate
              └── Parallel Index Only Scan using ix_lab04_ios_created
                    Heap Fetches: 188534
```

Index B-tree **không lưu thông tin MVCC** (xmin/xmax). Với mỗi entry tìm được, Index Only Scan
hỏi visibility map: "trang heap chứa dòng này có *all-visible* không?"

- Có → dòng chắc chắn hiển thị với mọi transaction → không cần đọc heap.
- Không → phải đọc trang heap để kiểm tra (`Heap Fetches` +1).

Bảng vừa `CREATE TABLE AS` + `ANALYZE` có visibility map **rỗng** (`relallvisible = 0`):
Index Only Scan thực chất đọc heap cho mọi dòng.

## Bottleneck

`Heap Fetches` bằng số dòng trả về: "index only" chỉ là trên danh nghĩa, Buffers (~2.5k) bao gồm
cả các trang heap.

## Optimization Strategy A

**VACUUM: fill the visibility map** — file [`02_optimize.sql`](02_optimize.sql)

```sql
VACUUM (ANALYZE) lab_ios;
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=4373.53..4373.54 rows=1 width=8) (actual time=5.191..5.917 rows=1 loops=1)
   Buffers: shared hit=522
   ->  Gather  (cost=4373.31..4373.52 rows=2 width=8) (actual time=5.165..5.915 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=522
         ->  Partial Aggregate  (cost=3373.31..3373.32 rows=1 width=8) (actual time=3.963..3.964 rows=1 loops=3)
               Buffers: shared hit=522
               ->  Parallel Index Only Scan using ix_lab04_ios_created on lab_ios  (actual time=0.007..2.666 rows=62845 loops=3)
                     Index Cond: ((lab_ios.created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone) AND (lab_ios.created_at < '2025 ...
                     Heap Fetches: 0
                     Buffers: shared hit=522
 Planning Time: 0.019 ms
 Execution Time: 5.922 ms
```

Q1: `Index Only Scan`, Heap Fetches 0, Buffers giảm ~5 lần. Q2 không đổi (vẫn cần heap).

## Why It Improved

`VACUUM` đánh dấu các trang mà mọi dòng đều đã hiển thị với mọi transaction (`relallvisible` ≈
`relpages`). Sau đó Q1: **Heap Fetches 0**, Buffers giảm từ ~2,541 xuống ~522 (chỉ còn các trang
index). Không có index mới nào — chỉ là siêu dữ liệu của bảng thay đổi.

## Trade-offs

- Visibility map bị xóa bit của một trang ngay khi có UPDATE/DELETE/INSERT trên trang đó → bảng
  ghi nhiều thì Index Only Scan dần trở lại đọc heap cho tới lần (auto)vacuum sau. Thử thí nghiệm
  UPDATE ở đầu `03_after.sql`.
- Autovacuum được kích hoạt theo số dòng *chết*; bảng chỉ INSERT (append-only) từ PG13 có
  `autovacuum_vacuum_insert_threshold` nhưng vẫn có độ trễ.

## Optimization Strategy B

**Covering index INCLUDE (total_amount) + VACUUM** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab04_ios_created_incl ON lab_ios (created_at) INCLUDE (total_amount);
VACUUM (ANALYZE) lab_ios;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Finalize Aggregate  (cost=4401.50..4401.51 rows=1 width=8) (actual time=4.780..5.587 rows=1 loops=1)
   Buffers: shared hit=522
   ->  Gather  (cost=4401.28..4401.49 rows=2 width=8) (actual time=4.726..5.585 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=522
         ->  Partial Aggregate  (cost=3401.28..3401.30 rows=1 width=8) (actual time=3.951..3.952 rows=1 loops=3)
               Buffers: shared hit=522
               ->  Parallel Index Only Scan using ix_lab04_ios_created on lab_ios  (actual time=0.009..2.657 rows=62845 loops=3)
                     Index Cond: ((lab_ios.created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone) AND (lab_ios.created_at < '2025 ...
                     Heap Fetches: 0
                     Buffers: shared hit=522
 Planning Time: 0.031 ms
 Execution Time: 5.595 ms
```

Index `INCLUDE (total_amount)` + VACUUM: cả Q2 thành `Index Only Scan` (Heap Fetches 0, Buffers giảm từ
~2,550 xuống ~730). Trên lab thời gian Q2 **không** giảm tương ứng: mọi trang đã nằm trong cache nên
khác biệt chủ yếu là số trang chạm tới, không phải I/O. Khi dữ liệu không nằm trong cache (bảng lớn
hơn RAM), chênh lệch Buffers mới chuyển thành chênh lệch thời gian.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Count orders in a date range: every needed column is in the index**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Index Only Scan using ix_lab04_ios_created on public.lab_ios` | 1 | 0 | shared hit=2541 | 10.7 ms |
| Strategy A | `Partial Aggregate, Parallel Index Only Scan using ix_lab04_ios_created on public.lab_ios` | 1 | 0 | shared hit=522 | 5.922 ms |
| Strategy B | `Partial Aggregate, Parallel Index Only Scan using ix_lab04_ios_created on public.lab_ios` | 1 | 0 | shared hit=522 | 5.595 ms |

**Q2 — Same range, but also reads total_amount (NOT in the index)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Index Scan using ix_lab04_ios_created on public.lab_ios` | 1 | 0 | shared hit=2555 | 7.763 ms |
| Strategy A | `Partial Aggregate, Parallel Index Scan using ix_lab04_ios_created on public.lab_ios` | 1 | 0 | shared hit=2552 | 7.676 ms |
| Strategy B | `Partial Aggregate, Parallel Index Only Scan using ix_lab04_ios_created_incl on public.lab_ios` | 1 | 0 | shared hit=729 | 10.4 ms |

## Reset

```sql
-- (strategy A has no object of its own: 05_reset.sql drops lab_ios)
DROP INDEX IF EXISTS ix_lab04_ios_created_incl;
DROP TABLE IF EXISTS lab_ios;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Index Only Scan` + `Heap Fetches: N`. N ≈ số dòng → visibility map chưa được set.
- `pg_class.relallvisible / relpages` trước và sau VACUUM.
- `Index Scan` (không "Only") khi query cần cột không có trong index.

## Interview Questions

1. Vì sao Index Only Scan vẫn có thể đọc heap?
2. Visibility map là gì, ai cập nhật nó, khi nào một bit bị xóa?
3. INCLUDE khác gì so với thêm cột vào key của index?
4. Bảng append-only có cần VACUUM không? Vì sao?
5. Làm sao biết một query đang được hưởng lợi từ Index Only Scan trên production?

## Key Takeaways

- Index Only Scan chỉ thực sự 'only' khi các trang heap đã all-visible trong visibility map.
- VACUUM không chỉ dọn dead tuple: nó còn bật visibility map cho Index Only Scan.
- INCLUDE thêm cột vào leaf của index để query trở thành index-only mà không đổi thứ tự sắp xếp.
- Ít buffers hơn chỉ thành ít thời gian hơn khi dữ liệu không nằm sẵn trong cache.

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
