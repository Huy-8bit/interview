# Lab 08 · Partial index: index only the rows you query

## Objective

Dùng **partial index** để chỉ index những dòng thực sự được truy vấn, và so sánh kích thước với
index đầy đủ bằng `pg_relation_size()`.

## Problem

Job đối soát chạy mỗi phút: lấy 100 payment PENDING cũ nhất trước một mốc thời gian. PENDING chỉ
chiếm ~8.5% của 5.1 triệu payment. Không có index phù hợp → mỗi lần chạy quét toàn bảng.

## Baseline Query

Q1 — Reconciliation job: oldest 100 PENDING payments before a cutoff

```sql
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'PENDING'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;
```

Q2 — Same shape, another status (FAILED)

```sql
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'FAILED'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Limit  (cost=139496.01..139507.68 rows=100 width=30) (actual time=114.083..116.192 rows=100 loops=1)
   Buffers: shared hit=458 read=101464
   ->  Gather Merge  (cost=139496.01..167538.10 rows=240344 width=30) (actual time=112.420..114.524 rows=100 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=458 read=101464
         ->  Sort  (cost=138495.99..138796.42 rows=120172 width=30) (actual time=105.503..105.505 rows=77 loops=3)
               Sort Key: payments.created_at
               Sort Method: top-N heapsort  Memory: 32kB
               Buffers: shared hit=458 read=101464
               ->  Parallel Seq Scan on payments  (actual time=51.996..104.401 rows=19339 loops=3)
                     Filter: ((payments.created_at < '2026-09-01 00:00:00+00'::timestamp with time zone) AND (payments.status = 'PENDING'::p ...
                     Rows Removed by Filter: 1690266
                     Buffers: shared hit=384 read=101464
 Planning Time: 0.047 ms
 Execution Time: 116.367 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Limit (100)
  └── Gather Merge                         <- trộn các kết quả đã sắp của worker
        └── Sort (top-N heapsort)          <- mỗi worker giữ 100 dòng tốt nhất
              └── Parallel Seq Scan on payments
                    Filter: status = 'PENDING' AND created_at < '2026-09-01'
```
Sau khi có index phù hợp:
```text
Limit (100)
  └── Index Scan using ix_lab08_payments_pending_created   <- đã sắp theo created_at, dừng sau 100
```

## Bottleneck

Seq Scan ~101k trang + `Rows Removed by Filter` ~1.69 triệu mỗi loop để trả 100 dòng.

## Optimization Strategy A

**Full composite index (status, created_at)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab08_payments_status_created ON payments (status, created_at);
```

## Result

AFTER Strategy A — Q1:

```text
 Limit  (cost=0.43..38.40 rows=100 width=30) (actual time=0.005..0.028 rows=100 loops=1)
   Buffers: shared hit=81
   ->  Index Scan using ix_lab08_payments_status_created on payments  (actual time=0.005..0.025 rows=100 loops=1)
         Index Cond: ((payments.status = 'PENDING'::payment_status) AND (payments.created_at < '2026-09-01 00:00:00+00'::timestamp with time ...
         Buffers: shared hit=81
 Planning Time: 0.014 ms
 Execution Time: 0.032 ms
```

Q1 và Q2 đều Index Scan + Limit, ~25–80 buffers.

## Why It Improved

Cả hai index đều cho plan `Index Scan` → `Limit` dừng sau 100 entry: ~80 buffers, dưới 0.1 ms.
Điểm khác là kích thước và phạm vi sử dụng (xem Strategy B).

## Trade-offs

- Index đầy đủ `(status, created_at)`: ~154 MB, phục vụ mọi status (Q2 cũng nhanh).
- Partial index: ~**9.6 MB** (nhỏ ~16 lần), nhưng chỉ dùng được cho query có điều kiện suy ra
  được `status = 'PENDING'`. Nếu ứng dụng đổi điều kiện (ví dụ `status IN ('PENDING', 'FAILED')`)
  hoặc truyền status bằng **tham số** của prepared statement ở generic plan, partial index có thể
  không còn dùng được.

## Optimization Strategy B

**Partial index (created_at) WHERE status = 'PENDING'** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab08_payments_pending_created ON payments (created_at) WHERE status = 'PENDING';
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Limit  (cost=0.42..4.46 rows=100 width=30) (actual time=0.004..0.025 rows=100 loops=1)
   Buffers: shared hit=81
   ->  Index Scan using ix_lab08_payments_pending_created on payments  (actual time=0.004..0.022 rows=100 loops=1)
         Index Cond: (payments.created_at < '2026-09-01 00:00:00+00'::timestamp with time zone)
         Buffers: shared hit=81
 Planning Time: 0.013 ms
 Execution Time: 0.029 ms
```

Q1: `Index Scan using ix_lab08_payments_pending_created` — cùng tốc độ với Strategy A với index nhỏ
hơn 16 lần. Q2 (FAILED) quay về Parallel Seq Scan: partial index không chứa các dòng đó.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Reconciliation job: oldest 100 PENDING payments before a cutoff**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Parallel Seq Scan on public.payments` | 100 | 1,690,266 | shared hit=458 read=101464 | 116.4 ms |
| Strategy A | `Index Scan using ix_lab08_payments_status_created on public.payments` | 100 | 0 | shared hit=81 | 0.032 ms |
| Strategy B | `Index Scan using ix_lab08_payments_pending_created on public.payments` | 100 | 0 | shared hit=81 | 0.029 ms |

**Q2 — Same shape, another status (FAILED)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Parallel Seq Scan on public.payments` | 100 | 1,614,378 | shared hit=746 read=101176 | 115.0 ms |
| Strategy A | `Index Scan using ix_lab08_payments_status_created on public.payments` | 100 | 0 | shared hit=25 | 0.021 ms |
| Strategy B | `Sort, Parallel Seq Scan on public.payments` | 100 | 1,614,378 | shared hit=1323 read=100599 | 115.4 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab08_payments_status_created;
DROP INDEX IF EXISTS ix_lab08_payments_pending_created;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Partial index xuất hiện trong plan chỉ khi WHERE của query *implies* predicate của index.
- `pg_get_indexdef()` hiện predicate (`WHERE (status = 'PENDING'::payment_status)`).
- So `pg_relation_size` của hai index.

## Interview Questions

1. Partial index được planner dùng khi nào?
2. Partial index có dùng được với prepared statement `WHERE status = $1` không?
3. So sánh partial index (created_at) WHERE status='PENDING' với index (status, created_at).
4. Partial unique index dùng để làm gì? (gợi ý: `ux_addresses_one_default_per_user`)

## Key Takeaways

- Partial index = index nhỏ cho phần dữ liệu 'nóng' (hàng đợi, trạng thái mở, bản ghi chưa xử lý).
- Nhỏ hơn → rẻ hơn khi ghi, dễ nằm trong cache hơn.
- Đổi lại, nó chỉ phục vụ đúng điều kiện đã định nghĩa.

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
