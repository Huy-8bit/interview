# Lab 39 · Buffer cache: shared hit vs read, cold vs warm, working set

## Objective

Hiểu `shared hit` vs `shared read`, cache lạnh vs cache ấm, vì sao không đo hiệu năng bằng một lần chạy,
và tối ưu bằng cách thu nhỏ *working set*.

## Problem

Doanh thu nửa cuối tháng 9 (~390k đơn) cần hai cột của mỗi đơn, nhưng phải đọc cả trang heap (~48k trang,
~390 MB). `shared_buffers` của lab là 256 MB.

## Baseline Query

Q1 — Revenue of the second half of September (reads ~800k order rows from the heap)

```sql
SELECT count(*), sum(total_amount)
FROM orders
WHERE created_at >= '2026-09-15';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=68321.31..68321.32 rows=1 width=40) (actual time=92.766..96.076 rows=1 loops=1)
   Buffers: shared hit=4004 read=48787 written=8
   ->  Gather  (cost=68321.08..68321.29 rows=2 width=40) (actual time=92.731..96.072 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=4004 read=48787 written=8
         ->  Partial Aggregate  (cost=67321.08..67321.09 rows=1 width=40) (actual time=91.255..91.255 rows=1 loops=3)
               Buffers: shared hit=4004 read=48787 written=8
               ->  Parallel Index Scan using idx_orders_created_at on orders  (actual time=0.031..69.615 rows=387942 loops=3)
                     Index Cond: (orders.created_at >= '2026-09-15 00:00:00+00'::timestamp with time zone)
                     Buffers: shared hit=4004 read=48787 written=8
 Planning Time: 0.061 ms
 Execution Time: 96.095 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Finalize Aggregate
  └── Gather → Partial Aggregate
        └── Parallel Index Scan using idx_orders_created_at   Buffers: shared hit=4004 read=48787
```
- **shared hit**: trang đã có trong `shared_buffers` của PostgreSQL.
- **shared read**: PostgreSQL phải xin trang từ OS. OS có thể trả từ **page cache** của nó (nhanh, không
  I/O đĩa) hoặc từ đĩa (chậm). EXPLAIN không phân biệt được hai trường hợp; `track_io_timing` (bật trong lab)
  cho biết thời gian chờ đọc.
- **Cold cache**: lần đầu sau khởi động / sau khi dữ liệu bị đẩy ra. **Warm cache**: các lần sau.
  Không dùng lệnh xoá cache của OS (cần root) — chỉ cần hiểu và chạy nhiều lần.

## Bottleneck

Quan sát thật: chạy lại lần thứ hai **vẫn** `read=48611` — working set (~390 MB) lớn hơn `shared_buffers`
(256 MB), nên các trang bị đẩy ra trước khi được dùng lại. `pg_buffercache` sau khi chạy: bảng `orders`
chiếm ~94% shared_buffers.

## Optimization Strategy A

**Shrink the working set: covering index (created_at) INCLUDE (total_amount)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab39_orders_created_amount ON orders (created_at) INCLUDE (total_amount);
VACUUM (ANALYZE) orders;
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=21960.02..21960.03 rows=1 width=40) (actual time=29.879..31.163 rows=1 loops=1)
   Buffers: shared hit=4472
   ->  Gather  (cost=21959.79..21960.00 rows=2 width=40) (actual time=29.847..31.158 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=4472
         ->  Partial Aggregate  (cost=20959.79..20959.80 rows=1 width=40) (actual time=28.308..28.308 rows=1 loops=3)
               Buffers: shared hit=4472
               ->  Parallel Index Only Scan using ix_lab39_orders_created_amount on orders  (actual time=0.012..15.105 rows=387942 loops=3)
                     Index Cond: (orders.created_at >= '2026-09-15 00:00:00+00'::timestamp with time zone)
                     Heap Fetches: 0
                     Buffers: shared hit=4472
 Planning Time: 0.053 ms
 Execution Time: 31.175 ms
```

`Parallel Index Only Scan using ix_lab39_orders_created_amount`, Heap Fetches 0, ~4.5k buffers toàn bộ là hit.

## Why It Improved

Covering index `(created_at) INCLUDE (total_amount)` chỉ lưu đúng hai cột, xếp chặt: cùng truy vấn cần
~4.5k trang thay vì ~53k — vừa trong shared_buffers, toàn bộ là `hit`, nhanh hơn ~3 lần và **ổn định** giữa
các lần chạy.

## Trade-offs

- Lần chạy thứ hai nhanh hơn lần đầu thường là do cache, **không phải** do plan tốt hơn. Phân biệt bằng cách so
  plan và tổng Buffers (hit + read): plan cải thiện làm *tổng* giảm; cache chỉ chuyển read thành hit.
- Quy tắc benchmark: chạy 5–10 lần, bỏ lần đầu nếu muốn đo trạng thái ấm, lấy trung vị; ghi lại cả Buffers.
- Tăng `shared_buffers` cũng là một lựa chọn (cần restart), nhưng thu nhỏ working set có lợi ở mọi kích thước RAM.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Revenue of the second half of September (reads ~800k order rows from the heap)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Index Scan using idx_orders_created_at on public.orders` | 1 | 0 | shared hit=4004 read=48787 written=8 | 96.1 ms |
| Strategy A | `Partial Aggregate, Parallel Index Only Scan using ix_lab39_orders_created_amount on public.orders` | 1 | 0 | shared hit=4472 | 31.2 ms |

Thử nghiệm của bạn: chạy `01_before.sql` 3 lần liên tiếp và ghi `hit` / `read` / thời gian của từng lần; rồi
chạy `00_environment/02_table_sizes.sql` và truy vấn `pg_buffercache` ở cuối `03_after.sql`.

## Reset

```sql
DROP INDEX IF EXISTS ix_lab39_orders_created_amount;
ANALYZE orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Buffers: shared hit=… read=…`: tổng = số trang chạm tới; tỉ lệ = hiệu quả cache.
- `I/O Timings: shared read=…` (khi `track_io_timing = on`).
- `pg_buffercache`: quan hệ nào đang chiếm shared_buffers.

## Interview Questions

1. shared hit và shared read khác nhau thế nào? shared read có phải luôn là đọc đĩa?
2. Vì sao lần chạy thứ hai thường nhanh hơn? Làm sao biết một tối ưu là thật?
3. Working set là gì? Vì sao nó quan trọng hơn kích thước bảng?
4. Cách benchmark một query cho đúng?

## Key Takeaways

- Đo nhiều lần, so Buffers chứ không chỉ thời gian.
- read → hit là hiệu ứng cache; tổng Buffers giảm mới là plan tốt hơn.
- Thu nhỏ working set (covering index, ít cột, partition) để dữ liệu nóng nằm trong cache.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
