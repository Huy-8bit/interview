# Lab 36 · VACUUM: dead tuples, visibility map, VACUUM vs VACUUM FULL

## Objective

Quan sát **dead tuple**, **visibility map** và tác dụng của `VACUUM` vs `VACUUM FULL` trên một bảng lab an toàn.

## Problem

Bảng lab `lab_vacuum` (1 triệu đơn) được VACUUM, rồi UPDATE 40% số dòng. Mỗi UPDATE tạo một phiên bản
dòng mới và để lại phiên bản cũ (dead tuple); trang bị sửa mất bit all-visible.

## Baseline Query

Q1 — Count a date range through the index (wants an Index Only Scan)

```sql
SELECT count(*)
FROM lab_vacuum
WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01';
```

Q2 — Full scan: dead tuples are read too

```sql
SELECT count(*), sum(total_amount)
FROM lab_vacuum;
```

## Expected Plan

Plan quan sát được (BEFORE): Index Only Scan nhưng `Heap Fetches` > số dòng trả về — các trang bị UPDATE
không còn all-visible, và mỗi dòng được cập nhật có hai entry index (phiên bản cũ + mới):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=5338.55..5338.56 rows=1 width=8) (actual time=8.334..9.490 rows=1 loops=1)
   Buffers: shared hit=88829
   ->  Gather  (cost=5338.33..5338.54 rows=2 width=8) (actual time=8.324..9.488 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=88829
         ->  Partial Aggregate  (cost=4338.33..4338.34 rows=1 width=8) (actual time=6.971..6.972 rows=1 loops=3)
               Buffers: shared hit=88829
               ->  Parallel Index Only Scan using ix_lab36_vacuum_created on lab_vacuum  (actual time=0.011..6.212 rows=36622 loops=3)
                     Index Cond: ((lab_vacuum.created_at >= '2025-01-01 00:00:00+00'::timestamp with time zone) AND (lab_vacuum.created_at < ...
                     Heap Fetches: 153814
                     Buffers: shared hit=88829
 Planning Time: 0.056 ms
 Execution Time: 9.501 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

MVCC: UPDATE = đánh dấu phiên bản cũ (`xmax`) + chèn phiên bản mới. Phiên bản cũ trở thành *dead* khi
không còn transaction nào có thể nhìn thấy nó. Chỉ **VACUUM** mới dọn nó.

```text
Finalize Aggregate
  └── Gather → Partial Aggregate
        └── Parallel Index Only Scan using ix_lab36_vacuum_created
              Heap Fetches: 153814       <- visibility map không giúp được
```
`pgstattuple('lab_vacuum')` cho số liệu chính xác: 400,000 dead tuple, ~27% bảng.

## Bottleneck

Index Only Scan phải đọc heap cho hầu hết các dòng; Seq Scan đọc cả không gian của dead tuple.

## Optimization Strategy A

**VACUUM (VERBOSE): remove dead tuples, set the visibility map** — file [`02_optimize.sql`](02_optimize.sql)

```sql
-- hot_standby_feedback (on in this lab): the replica reports its oldest snapshot to the
    -- primary through the replication slot (pg_replication_slots.xmin) about once per second.
    -- Until that report covers the changes made just above, the primary must assume the
    -- replica still needs the old row versions, and VACUUM / VACUUM FULL / REINDEX keep them
    -- ("dead but not yet removable"). Wait for the report (at most 10 s) so the lab is repeatable.
    DO $$
    DECLARE
      target bigint := pg_snapshot_xmax(pg_current_snapshot())::text::bigint;   -- next xid, none assigned
    BEGIN
      FOR i IN 1..50 LOOP
        EXIT WHEN NOT EXISTS (SELECT 1 FROM pg_replication_slots
                              WHERE xmin IS NOT NULL AND xmin::text::bigint < target);
        PERFORM pg_sleep(0.2);
      END LOOP;
    END $$;
    SELECT slot_name, xmin AS slot_xmin FROM pg_replication_slots;

VACUUM (VERBOSE, ANALYZE) lab_vacuum;
```

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=3125.21..3125.22 rows=1 width=8) (actual time=7.261..7.261 rows=1 loops=1)
   Buffers: shared hit=605
   ->  Index Only Scan using ix_lab36_vacuum_created on lab_vacuum  (actual time=0.002..4.730 rows=109867 loops=1)
         Index Cond: ((lab_vacuum.created_at >= '2025-01-01 00:00:00+00'::timestamp with time zone) AND (lab_vacuum.created_at < '2025-04-01 ...
         Heap Fetches: 0
         Buffers: shared hit=605
 Planning Time: 0.011 ms
 Execution Time: 7.264 ms
```

400,000 dead tuple bị xoá, `relallvisible` đầy, Heap Fetches 0; kích thước vẫn 91 MB.

## Why It Improved

`VACUUM (VERBOSE)`: `tuples: 400000 removed`, visibility map được set lại (`relallvisible = relpages`)
→ Index Only Scan **Heap Fetches 0**, Buffers giảm mạnh. Kích thước file **không đổi** (91 MB): không gian
được đưa vào free space map để dòng mới tái sử dụng, không trả lại cho OS.

**Bài học phụ quan sát được khi tự động hoá lab**: chạy VACUUM ngay sau UPDATE, log báo
`400000 are dead but not yet removable` — replica (với `hot_standby_feedback = on`) chưa kịp báo snapshot
mới qua replication slot (~1 giây/lần), nên primary phải giữ các phiên bản cũ. Các file của lab chờ báo cáo
đó (tối đa 10 s) trước khi VACUUM. Trên production, một query dài trên replica có thể chặn VACUUM trên primary
như vậy hàng giờ (xem [`docs/transaction-lab.md` §8.2](../../../docs/transaction-lab.md)).

## Trade-offs

- VACUUM: lock `SHARE UPDATE EXCLUSIVE` — đọc/ghi vẫn chạy; không thu nhỏ file.
- VACUUM FULL: thu nhỏ file nhưng lock `ACCESS EXCLUSIVE` (chặn cả SELECT) suốt quá trình và cần chỗ trống
  cho bản sao — hiếm khi chấp nhận được trên production (dùng `pg_repack` / `pg_squeeze` thay thế).
- Autovacuum làm việc này tự động; lab tắt nó trên bảng lab để giữ dead tuple.

## Optimization Strategy B

**VACUUM FULL: rewrite the table compactly** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
-- hot_standby_feedback (on in this lab): the replica reports its oldest snapshot to the
    -- primary through the replication slot (pg_replication_slots.xmin) about once per second.
    -- Until that report covers the changes made just above, the primary must assume the
    -- replica still needs the old row versions, and VACUUM / VACUUM FULL / REINDEX keep them
    -- ("dead but not yet removable"). Wait for the report (at most 10 s) so the lab is repeatable.
    DO $$
    DECLARE
      target bigint := pg_snapshot_xmax(pg_current_snapshot())::text::bigint;   -- next xid, none assigned
    BEGIN
      FOR i IN 1..50 LOOP
        EXIT WHEN NOT EXISTS (SELECT 1 FROM pg_replication_slots
                              WHERE xmin IS NOT NULL AND xmin::text::bigint < target);
        PERFORM pg_sleep(0.2);
      END LOOP;
    END $$;
    SELECT slot_name, xmin AS slot_xmin FROM pg_replication_slots;

VACUUM (FULL, VERBOSE, ANALYZE) lab_vacuum;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=9712.25..9712.26 rows=1 width=8) (actual time=11.115..11.116 rows=1 loops=1)
   Buffers: shared hit=44618
   ->  Index Only Scan using ix_lab36_vacuum_created on lab_vacuum  (actual time=0.005..8.875 rows=109867 loops=1)
         Index Cond: ((lab_vacuum.created_at >= '2025-01-01 00:00:00+00'::timestamp with time zone) AND (lab_vacuum.created_at < '2025-04-01 ...
         Heap Fetches: 109867
         Buffers: shared hit=44618
 Planning Time: 0.027 ms
 Execution Time: 11.122 ms
```

`VACUUM FULL`: bảng viết lại còn ~65 MB, không dead tuple; nhưng bảng bị khoá hoàn toàn trong lúc chạy.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Count a date range through the index (wants an Index Only Scan)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Index Only Scan using ix_lab36_vacuum_created on public.lab_vacuum` | 1 | 0 | shared hit=88829 | 9.501 ms |
| Strategy A | `Index Only Scan using ix_lab36_vacuum_created on public.lab_vacuum` | 1 | 0 | shared hit=605 | 7.264 ms |
| Strategy B | `Index Only Scan using ix_lab36_vacuum_created on public.lab_vacuum` | 1 | 0 | shared hit=44618 | 11.1 ms |

**Q2 — Full scan: dead tuples are read too**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.lab_vacuum` | 1 | 0 | shared hit=11667 | 29.6 ms |
| Strategy A | `Partial Aggregate, Parallel Seq Scan on public.lab_vacuum` | 1 | 0 | shared hit=11667 | 26.4 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.lab_vacuum` | 1 | 0 | shared hit=1366 read=6968 | 30.0 ms |

## Reset

```sql
-- (no object of its own: 05_reset.sql drops lab_vacuum)
-- (no object of its own: 05_reset.sql drops lab_vacuum)
DROP TABLE IF EXISTS lab_vacuum;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Heap Fetches` của Index Only Scan.
- `VACUUM (VERBOSE)`: `tuples: N removed, M remain, K are dead but not yet removable`, `removable cutoff`.
- `pgstattuple`: `dead_tuple_count`, `free_percent`; `pg_class.relallvisible / relpages`.

## Interview Questions

1. Dead tuple là gì? Vì sao UPDATE tạo ra dead tuple?
2. VACUUM và VACUUM FULL khác nhau thế nào về kết quả và lock?
3. 'dead but not yet removable' nghĩa là gì? Những gì có thể gây ra nó?
4. hot_standby_feedback ảnh hưởng thế nào đến VACUUM trên primary?
5. Visibility map dùng để làm gì (2 việc)?

## Key Takeaways

- UPDATE/DELETE để lại dead tuple; VACUUM dọn chúng và set visibility map.
- VACUUM không trả dung lượng cho OS; VACUUM FULL có nhưng khoá bảng.
- Một snapshot cũ ở bất kỳ đâu (kể cả trên replica) chặn VACUUM.

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
