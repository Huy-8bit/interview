# Lab 15 · Indexes are not free: INSERT / UPDATE / DELETE cost and WAL

## Objective

Đo chi phí của index với các thao tác ghi: thời gian, WAL, buffers — để hiểu vì sao 'index everything' là anti-pattern.

## Problem

Một bảng có hình dạng như `orders` (`lab_write`, 500k dòng, chỉ có primary key). Đo INSERT 200k
dòng, UPDATE 100k dòng, DELETE 50k dòng — trước và sau khi thêm 4 index phụ. Mọi DML chạy trong
`BEGIN … ROLLBACK` nên lần đo nào cũng giống nhau và dữ liệu không đổi.

## Baseline Query

Q1 — INSERT 200,000 rows

```sql
INSERT INTO lab_write
SELECT * FROM orders WHERE id > 500000 AND id <= 700000;
```

Q2 — UPDATE an indexed column (status) on 100,000 rows

```sql
UPDATE lab_write SET status = 'CANCELLED'
WHERE id <= 100000;
```

Q3 — DELETE 50,000 rows

```sql
DELETE FROM lab_write
WHERE id <= 50000;
```

## Expected Plan

Plan quan sát được (BEFORE, chỉ có primary key) — chú ý dòng `WAL:` ở node trên cùng:

BEFORE — Q1:

```text
 Insert on lab_write  (cost=0.43..12011.37 rows=0 width=0) (actual time=691.509..691.509 rows=0 loops=1)
   Buffers: shared hit=419426 read=8548 dirtied=8548 written=10777
   WAL: records=400550 fpi=2 bytes=82651634
   ->  Index Scan using pk_orders on orders  (cost=0.43..12011.37 rows=190577 width=309) (actual time=0.046..181.732 rows=200000 loops=1)
         Index Cond: ((orders.id > 500000) AND (orders.id <= 700000))
         Buffers: shared hit=7 read=8548 written=1114
 Planning Time: 0.032 ms
 Execution Time: 691.776 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Insert on lab_write
  WAL: records=400550 bytes=82651634
  └── Index Scan using pk_orders on orders  (nguồn dữ liệu)
```

Mỗi dòng INSERT ghi: 1 heap tuple + 1 entry cho **mỗi** index, mỗi thao tác sinh WAL record và làm
bẩn (dirty) trang. Với UPDATE, nếu cột được cập nhật nằm trong một index thì không thể **HOT update**
(Heap-Only Tuple): phiên bản dòng mới cần entry mới trong *mọi* index, kể cả index không chứa cột đó.
DELETE chỉ đánh dấu `xmax` trên heap; entry trong index được dọn sau bởi VACUUM.

## Bottleneck

Không có bottleneck ở baseline: đây là mốc so sánh cho chi phí ghi.

## Optimization Strategy A

**Four secondary indexes (a typical 'index everything' table)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab15_write_user        ON lab_write (user_id);
CREATE INDEX ix_lab15_write_status_time ON lab_write (status, created_at);
CREATE INDEX ix_lab15_write_created     ON lab_write (created_at);
CREATE UNIQUE INDEX ix_lab15_write_number ON lab_write (order_number);
```

## Result

AFTER Strategy A — Q1:

```text
 Insert on lab_write  (cost=0.43..12011.37 rows=0 width=0) (actual time=2147.070..2147.070 rows=0 loops=1)
   Buffers: shared hit=2622194 read=9842 dirtied=13031 written=26116
   WAL: records=1211072 fpi=2 bytes=146112262
   ->  Index Scan using pk_orders on orders  (cost=0.43..12011.37 rows=190577 width=309) (actual time=0.075..150.382 rows=200000 loops=1)
         Index Cond: ((orders.id > 500000) AND (orders.id <= 700000))
         Buffers: shared hit=5 read=8550 written=5947
 Planning Time: 0.035 ms
 Execution Time: 2147.125 ms
```

Mọi INSERT/UPDATE chậm hơn đáng kể và sinh nhiều WAL hơn; DELETE gần như không đổi về WAL.

## Why It Improved

Lab này đi theo chiều ngược lại: thêm index làm ghi **chậm hơn**. Số đo thật trên lab (xem bảng):

- INSERT: ~3 lần thời gian, WAL từ ~83 MB lên ~146 MB (4 index phụ).
- UPDATE status: ~3.7 lần thời gian, WAL từ ~50 MB lên ~83 MB.
- DELETE: WAL **giống hệt** (50,000 records, 2.7 MB): DELETE không chạm index.
- Strategy B (một index phụ) nằm ở giữa.

## Trade-offs

- Mỗi index: thêm dung lượng, thêm WAL (cũng là thêm băng thông replication và dung lượng backup/PITR),
  thêm thời gian VACUUM, giảm HOT update.
- Index không dùng đến (`pg_stat_user_indexes.idx_scan = 0`) là chi phí thuần — tìm và drop chúng
  (`00_environment/07_index_usage.sql`).
- Với bulk load lớn, thường drop index phụ → nạp → tạo lại (chính generator của lab làm vậy).

## Optimization Strategy B

**Only the one index the application really needs (user_id)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab15_write_user_only ON lab_write (user_id);
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Insert on lab_write  (cost=0.43..12011.37 rows=0 width=0) (actual time=1099.093..1099.094 rows=0 loops=1)
   Buffers: shared hit=1595520 read=9826 dirtied=10707 written=24281
   WAL: records=608762 fpi=13 bytes=101047005
   ->  Index Scan using pk_orders on orders  (cost=0.43..12011.37 rows=190577 width=309) (actual time=0.134..97.026 rows=200000 loops=1)
         Index Cond: ((orders.id > 500000) AND (orders.id <= 700000))
         Buffers: shared hit=5 read=8550 written=6952
 Planning Time: 0.034 ms
 Execution Time: 1099.161 ms
```

Chỉ một index phụ: chi phí nằm giữa bảng trần và Strategy A — chỉ tạo index mà ứng dụng thật sự cần.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — INSERT 200,000 rows**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using pk_orders on public.orders` | 0 | 0 | shared hit=419426 read=8548 dirtied=8548 written=10777 · WAL records=400550 fpi=2 bytes=82651634 | 691.8 ms |
| Strategy A | `Index Scan using pk_orders on public.orders` | 0 | 0 | shared hit=2622194 read=9842 dirtied=13031 written=26116 · WAL records=1211072 fpi=2 bytes=146112262 | 2,147.1 ms |
| Strategy B | `Index Scan using pk_orders on public.orders` | 0 | 0 | shared hit=1595520 read=9826 dirtied=10707 written=24281 · WAL records=608762 fpi=13 bytes=101047005 | 1,099.2 ms |

**Q2 — UPDATE an indexed column (status) on 100,000 rows**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using lab_write_pkey on public.lab_write` | 0 | 0 | shared hit=709718 read=4275 dirtied=8550 written=10661 · WAL records=301349 fpi=1 bytes=49676005 | 447.9 ms |
| Strategy A | `Index Scan using lab_write_pkey on public.lab_write` | 0 | 0 | shared hit=2262662 read=6056 dirtied=10330 written=10005 · WAL records=710316 fpi=1 bytes=83144115 | 1,636.3 ms |
| Strategy B | `Index Scan using lab_write_pkey on public.lab_write` | 0 | 0 | shared hit=1257165 read=3712 dirtied=7921 written=4281 · WAL records=402735 fpi=11 bytes=55536947 | 733.5 ms |

**Q3 — DELETE 50,000 rows**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using lab_write_pkey on public.lab_write` | 0 | 0 | shared hit=150550 · WAL records=50000 bytes=2700000 | 38.8 ms |
| Strategy A | `Index Scan using lab_write_pkey on public.lab_write` | 0 | 0 | shared hit=164713 read=1109 dirtied=1111 written=1039 · WAL records=50000 bytes=2700000 | 181.1 ms |
| Strategy B | `Index Scan using lab_write_pkey on public.lab_write` | 0 | 0 | shared hit=165820 read=2 dirtied=82 · WAL records=50000 bytes=2700000 | 51.9 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab15_write_user;
DROP INDEX IF EXISTS ix_lab15_write_status_time;
DROP INDEX IF EXISTS ix_lab15_write_created;
DROP INDEX IF EXISTS ix_lab15_write_number;
DROP INDEX IF EXISTS ix_lab15_write_user_only;
DROP TABLE IF EXISTS lab_write;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `EXPLAIN (ANALYZE, BUFFERS, WAL, VERBOSE)` trên DML: dòng `WAL: records=… fpi=… bytes=…`.
- `fpi` (full page image): trang đầu tiên được sửa sau mỗi checkpoint được ghi nguyên trang vào WAL.
- `Buffers: shared dirtied / written`.
- Luôn bọc EXPLAIN ANALYZE của DML trong `BEGIN … ROLLBACK`.

## Interview Questions

1. Vì sao index làm INSERT/UPDATE chậm hơn? DELETE thì sao?
2. HOT update là gì? Điều kiện để một UPDATE là HOT?
3. Index ảnh hưởng thế nào đến WAL và replication?
4. Làm sao tìm index không được dùng? Cần cẩn thận gì trước khi drop?
5. EXPLAIN ANALYZE một câu UPDATE có thay đổi dữ liệu không? Làm sao chạy an toàn?

## Key Takeaways

- Index tăng tốc đọc bằng cách làm chậm ghi.
- Mỗi index thêm WAL: ảnh hưởng replica, backup, dung lượng.
- Index trên cột hay cập nhật chặn HOT update.
- Chỉ tạo index cho query thực sự cần; định kỳ dọn index không dùng.

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
