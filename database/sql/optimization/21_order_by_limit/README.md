# Lab 21 · ORDER BY ... LIMIT: top-N heapsort vs Index Scan Backward

## Objective

So sánh `ORDER BY … LIMIT` khi phải sort (top-N heapsort) và khi index cung cấp sẵn thứ tự (Index Scan Backward).

## Problem

Màn hình 'giao dịch mới nhất' và 'giao dịch FAILED mới nhất': 50 dòng từ 5.1 triệu payment, không có index trên `created_at`.

## Baseline Query

Q1 — Latest 50 payments

```sql
SELECT id, order_id, amount, status, created_at
FROM payments
ORDER BY created_at DESC
LIMIT 50;
```

Q2 — Latest 50 FAILED payments

```sql
SELECT id, order_id, amount, status, created_at
FROM payments
WHERE status = 'FAILED'
ORDER BY created_at DESC
LIMIT 50;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Limit  (cost=195207.93..195213.76 rows=50 width=34) (actual time=269.276..271.420 rows=50 loops=1)
   Buffers: shared hit=266 read=101656
   ->  Gather Merge  (cost=195207.93..693877.71 rows=4274014 width=34) (actual time=267.541..269.684 rows=50 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=266 read=101656
         ->  Sort  (cost=194207.90..199550.42 rows=2137007 width=34) (actual time=258.625..258.626 rows=34 loops=3)
               Sort Key: payments.created_at DESC
               Sort Method: top-N heapsort  Memory: 32kB
               Buffers: shared hit=266 read=101656
               ->  Parallel Seq Scan on payments  (actual time=1.282..125.148 rows=1709605 loops=3)
                     Buffers: shared hit=192 read=101656
 Planning Time: 0.053 ms
 Execution Time: 271.564 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Limit (50)
  └── Gather Merge                     (3) trộn các danh sách đã sắp của worker
        └── Sort  top-N heapsort       (2) mỗi worker giữ 50 dòng mới nhất
              └── Parallel Seq Scan on payments   (1) đọc TẤT CẢ các dòng
```
top-N heapsort chỉ cần bộ nhớ cho N dòng, nhưng vẫn phải **đọc mọi dòng** để biết đâu là N dòng
mới nhất. Với index trên `created_at`:
```text
Limit (50)
  └── Index Scan Backward using ix_lab21_payments_created   <- đọc từ cuối index, dừng sau 50
```

## Bottleneck

~102k trang được đọc để trả 50 dòng.

## Optimization Strategy A

**Index on payments(created_at)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab21_payments_created ON payments (created_at);
```

## Result

AFTER Strategy A — Q1:

```text
 Limit  (cost=0.43..2.33 rows=50 width=34) (actual time=0.002..0.008 rows=50 loops=1)
   Buffers: shared hit=5
   ->  Index Scan Backward using ix_lab21_payments_created on payments  (actual time=0.002..0.006 rows=50 loops=1)
         Buffers: shared hit=5
 Planning Time: 0.009 ms
 Execution Time: 0.011 ms
```

Q1 và Q2: `Index Scan Backward using ix_lab21_payments_created`, không còn Sort.

## Why It Improved

Index Scan Backward đọc ~5 trang và dừng: từ hàng trăm ms xuống micro giây. Với Q2 (FAILED) cùng index,
scan backward phải bỏ qua các payment không FAILED (`Rows Removed by Filter` ~900) nhưng vẫn rất nhanh vì
FAILED đủ phổ biến (~7%).

## Trade-offs

- Index `(created_at)` ~110 MB; ghi thêm cho mỗi payment.
- Q2 với giá trị **hiếm** (ví dụ một status 0.01%) sẽ phải lùi rất xa trong index → khi đó cần `(status, created_at)`.

## Optimization Strategy B

**Index on payments(status, created_at)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab21_payments_status_created ON payments (status, created_at);
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Limit  (cost=195207.93..195213.76 rows=50 width=34) (actual time=327.294..329.484 rows=50 loops=1)
   Buffers: shared hit=1034 read=100888
   ->  Gather Merge  (cost=195207.93..693877.71 rows=4274014 width=34) (actual time=326.052..328.240 rows=50 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=1034 read=100888
         ->  Sort  (cost=194207.90..199550.42 rows=2137007 width=34) (actual time=318.887..318.891 rows=50 loops=3)
               Sort Key: payments.created_at DESC
               Sort Method: top-N heapsort  Memory: 32kB
               Buffers: shared hit=1034 read=100888
               ->  Parallel Seq Scan on payments  (actual time=1.001..168.240 rows=1709605 loops=3)
                     Buffers: shared hit=960 read=100888
 Planning Time: 0.048 ms
 Execution Time: 329.619 ms
```

`(status, created_at)`: Q2 đọc đúng 50 entry (không Filter); **Q1 quay về Seq Scan + Sort** vì không có điều kiện trên cột đầu `status`.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Latest 50 payments**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Parallel Seq Scan on public.payments` | 50 | 0 | shared hit=266 read=101656 | 271.6 ms |
| Strategy A | `Index Scan Backward using ix_lab21_payments_created on public.payments` | 50 | 0 | shared hit=5 | 0.011 ms |
| Strategy B | `Sort, Parallel Seq Scan on public.payments` | 50 | 0 | shared hit=1034 read=100888 | 329.6 ms |

**Q2 — Latest 50 FAILED payments**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Parallel Seq Scan on public.payments` | 50 | 1,586,099 | shared hit=554 read=101368 | 120.9 ms |
| Strategy A | `Index Scan Backward using ix_lab21_payments_created on public.payments` | 50 | 931 | shared hit=570 | 0.099 ms |
| Strategy B | `Index Scan Backward using ix_lab21_payments_status_created on public.payments` | 50 | 0 | shared hit=43 | 0.013 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab21_payments_created;
DROP INDEX IF EXISTS ix_lab21_payments_status_created;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Sort Method: top-N heapsort` dưới `Limit`: đã đọc toàn bộ đầu vào.
- `Index Scan Backward` dưới `Limit`, không có Sort: thứ tự từ index.
- `Rows Removed by Filter` trên scan backward: số dòng phải bỏ qua trước khi đủ LIMIT.

## Interview Questions

1. top-N heapsort là gì? Bộ nhớ và số dòng đọc của nó thế nào?
2. Index B-tree có đọc ngược được không? DESC trong index có cần thiết không?
3. Index nào cho `WHERE status = ? ORDER BY created_at DESC LIMIT 50`?
4. Vì sao một index (status, created_at) không giúp `ORDER BY created_at` không có điều kiện status?

## Key Takeaways

- ORDER BY + LIMIT nhỏ: một index đúng thứ tự biến 'đọc tất cả' thành 'đọc N'.
- B-tree đọc được cả hai chiều; DESC chỉ quan trọng khi trộn chiều giữa các cột.
- Cột lọc bằng đứng trước cột ORDER BY trong index.

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
