# Lab 12 · JSONB: GIN jsonb_ops vs jsonb_path_ops vs expression B-tree

## Objective

Chọn đúng loại index cho **JSONB**: GIN `jsonb_ops`, GIN `jsonb_path_ops`, hay B-tree trên một biểu
thức — và nhận ra khi nào không index nào giúp được.

## Problem

`users.metadata` (JSONB) chứa signup_source, preferred_language, tags, referred_by... Ba câu hỏi:
user có tag `wholesale` (0.3%), user có key `referred_by` (8%), user có `preferred_language = 'ja'`
(3.8%). Không có index → mỗi câu parse toàn bộ 5 triệu document.

## Baseline Query

Q1 — Containment: users tagged 'wholesale' (~15k of 5M)

```sql
SELECT count(*)
FROM users
WHERE metadata @> '{"tags": ["wholesale"]}';
```

Q2 — Key existence: users with a 'referred_by' key (~8%)

```sql
SELECT count(*)
FROM users
WHERE metadata ? 'referred_by';
```

Q3 — One scalar field: preferred_language = 'ja' (~3.8%)

```sql
SELECT count(*)
FROM users
WHERE metadata ->> 'preferred_language' = 'ja';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=277260.40..277260.41 rows=1 width=8) (actual time=250.105..252.119 rows=1 loops=1)
   Buffers: shared hit=1474 read=248726
   ->  Gather  (cost=277260.18..277260.40 rows=2 width=8) (actual time=250.026..252.113 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=1474 read=248726
         ->  Partial Aggregate  (cost=276260.18..276260.20 rows=1 width=8) (actual time=243.408..243.409 rows=1 loops=3)
               Buffers: shared hit=1474 read=248726
               ->  Parallel Seq Scan on users  (cost=0.00..276244.56 rows=6249 width=0) (actual time=2.190..243.113 rows=4982 loops=3)
                     Filter: (users.metadata @> '{"tags": ["wholesale"]}'::jsonb)
                     Rows Removed by Filter: 1661685
                     Buffers: shared hit=1474 read=248726
 Planning Time: 0.056 ms
 Execution Time: 252.292 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

GIN là *inverted index*: mỗi key/value trong JSON là một entry, trỏ tới danh sách các dòng chứa nó.

```text
Aggregate
  └── Bitmap Heap Scan on users
        Recheck Cond: (metadata @> '{"tags": ["wholesale"]}')
        └── Bitmap Index Scan on ix_lab12_users_metadata_gin
```
GIN luôn đi qua bitmap (không có "GIN Index Scan" trả dòng theo thứ tự).

## Bottleneck

Seq Scan ~250k trang users cho mỗi câu hỏi.

## Optimization Strategy A

**GIN (metadata) with the default jsonb_ops** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab12_users_metadata_gin ON users USING gin (metadata);
```

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=15985.41..15985.42 rows=1 width=8) (actual time=12.204..12.204 rows=1 loops=1)
   Buffers: shared hit=14662
   ->  Bitmap Heap Scan on users  (cost=94.63..15947.92 rows=14997 width=0) (actual time=3.439..11.905 rows=14945 loops=1)
         Recheck Cond: (users.metadata @> '{"tags": ["wholesale"]}'::jsonb)
         Heap Blocks: exact=14543
         Buffers: shared hit=14662
         ->  Bitmap Index Scan on ix_lab12_users_metadata_gin  (actual time=2.231..2.231 rows=14945 loops=1)
               Index Cond: (users.metadata @> '{"tags": ["wholesale"]}'::jsonb)
               Buffers: shared hit=119
   Buffers: shared hit=1
 Planning Time: 0.075 ms
 Execution Time: 12.281 ms
```

Q1 Bitmap Heap Scan qua GIN (~12 ms). Q2 dùng GIN nhưng bitmap lossy, chậm hơn Seq Scan. Q3 không dùng được GIN (`->>` không phải operator của GIN).

## Why It Improved

Q1 (`@>`, 0.3% dòng): GIN biến 250 ms thành ~12 ms — chỉ đọc ~14.5k trang chứa 15k dòng khớp.

## Trade-offs

Đây là lab có nhiều kết quả "ngược" nhất, tất cả đều quan sát thật trên dataset:

- Q2 (`? 'referred_by'`, 8% dòng) với `jsonb_ops`: planner dùng GIN, bitmap 400k TID **không vừa
  work_mem** → lossy (`Heap Blocks: lossy=46554`, `Rows Removed by Index Recheck` ~800k mỗi worker) →
  **chậm hơn Seq Scan**.
- Q3 với B-tree expression (Strategy C): Index Scan 190k dòng rải rác đọc ngẫu nhiên ~135k trang →
  **chậm hơn Seq Scan**. Index đúng về mặt kỹ thuật nhưng selectivity 3.8% trên một bảng mà mỗi trang
  chỉ chứa ~20 dòng là quá cao để index có lợi.
- GIN tốn ghi: mỗi UPDATE metadata cập nhật nhiều entry (giảm nhờ `fastupdate` pending list, đổi lại
  query phải đọc thêm pending list).
- Kích thước: jsonb_ops 84 MB, jsonb_path_ops 52 MB, B-tree expression 33 MB.

## Optimization Strategy B

**GIN (metadata jsonb_path_ops)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab12_users_metadata_pathops ON users USING gin (metadata jsonb_path_ops);
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=15812.91..15812.92 rows=1 width=8) (actual time=10.890..10.890 rows=1 loops=1)
   Buffers: shared hit=14553
   ->  Bitmap Heap Scan on users  (cost=89.50..15775.83 rows=14833 width=0) (actual time=2.193..10.587 rows=14945 loops=1)
         Recheck Cond: (users.metadata @> '{"tags": ["wholesale"]}'::jsonb)
         Heap Blocks: exact=14543
         Buffers: shared hit=14553
         ->  Bitmap Index Scan on ix_lab12_users_metadata_pathops  (actual time=1.051..1.051 rows=14945 loops=1)
               Index Cond: (users.metadata @> '{"tags": ["wholesale"]}'::jsonb)
               Buffers: shared hit=10
   Buffers: shared hit=1
 Planning Time: 0.045 ms
 Execution Time: 10.945 ms
```

Q1 tương đương A với index nhỏ hơn (52 MB). Q2 quay về Seq Scan: `jsonb_path_ops` không hỗ trợ `?`.

## Optimization Strategy C

**B-tree expression index on (metadata ->> 'preferred_language')** — file [`02c_strategy_c.sql`](02c_strategy_c.sql)

```sql
CREATE INDEX ix_lab12_users_pref_lang ON users ((metadata ->> 'preferred_language'));
ANALYZE users;
```

## Result (Strategy C)

AFTER Strategy C — Q1:

```text
 Finalize Aggregate  (cost=277255.47..277255.48 rows=1 width=8) (actual time=256.373..259.614 rows=1 loops=1)
   Buffers: shared hit=26446 read=223754
   ->  Gather  (cost=277255.26..277255.47 rows=2 width=8) (actual time=256.283..259.607 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=26446 read=223754
         ->  Partial Aggregate  (cost=276255.26..276255.27 rows=1 width=8) (actual time=249.790..249.790 rows=1 loops=3)
               Buffers: shared hit=26446 read=223754
               ->  Parallel Seq Scan on users  (cost=0.00..276239.74 rows=6208 width=0) (actual time=2.044..249.482 rows=4982 loops=3)
                     Filter: (users.metadata @> '{"tags": ["wholesale"]}'::jsonb)
                     Rows Removed by Filter: 1661685
                     Buffers: shared hit=26446 read=223754
 Planning Time: 0.053 ms
 Execution Time: 259.797 ms
```

Q3 dùng B-tree expression index nhưng chậm hơn Seq Scan (đọc ngẫu nhiên 135k trang). Q1, Q2 không đổi.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Containment: users tagged 'wholesale' (~15k of 5M)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,661,685 | shared hit=1474 read=248726 | 252.3 ms |
| Strategy A | `Bitmap Heap Scan on public.users, Bitmap Index Scan on ix_lab12_users_metadata_gin` | 1 | 0 | shared hit=14662 | 12.3 ms |
| Strategy B | `Bitmap Heap Scan on public.users, Bitmap Index Scan on ix_lab12_users_metadata_pathops` | 1 | 0 | shared hit=14553 | 10.9 ms |
| Strategy C | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,661,685 | shared hit=26446 read=223754 | 259.8 ms |

**Q2 — Key existence: users with a 'referred_by' key (~8%)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,533,111 | shared hit=1762 read=248438 | 212.6 ms |
| Strategy A | `Partial Aggregate, Parallel Bitmap Heap Scan on public.users, Bitmap Index Scan on ix_lab12_users_metadata_gin` | 1 | 0 | shared hit=1 read=203381 | 355.5 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,533,111 | shared hit=25752 read=224448 | 226.7 ms |
| Strategy C | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,533,111 | shared hit=26734 read=223466 | 221.0 ms |

**Q3 — One scalar field: preferred_language = 'ja' (~3.8%)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,603,402 | shared hit=2050 read=248150 | 346.0 ms |
| Strategy A | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,603,402 | shared hit=32574 read=217626 | 251.8 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 1,603,402 | shared hit=25998 read=224202 | 257.2 ms |
| Strategy C | `Index Scan using ix_lab12_users_pref_lang on public.users` | 1 | 0 | shared read=135058 | 360.3 ms |

Chọn: `jsonb_path_ops` nếu chỉ cần `@>`; `jsonb_ops` nếu cần `?`/`?|`/`?&`; B-tree trên
`(metadata ->> 'field')` cho một field cố định cần `=`, range, ORDER BY và **selectivity thấp**.
Với điều kiện khớp vài % số dòng của một bảng lớn, không index nào thắng Seq Scan song song.

## Reset

```sql
DROP INDEX IF EXISTS ix_lab12_users_metadata_gin;
DROP INDEX IF EXISTS ix_lab12_users_metadata_pathops;
DROP INDEX IF EXISTS ix_lab12_users_pref_lang;
ANALYZE users;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Bitmap Index Scan on <gin>` + `Heap Blocks: exact / lossy`.
- Operator trong `Recheck Cond` / `Filter`: `@>`, `?` (GIN) vs `->>` (chỉ B-tree expression).
- Bitmap lossy → cân nhắc `work_mem` hoặc kết luận index không phù hợp với selectivity này.

## Interview Questions

1. jsonb_ops và jsonb_path_ops khác nhau thế nào? Khi nào dùng cái nào?
2. Vì sao `metadata ->> 'x' = 'y'` không dùng GIN index?
3. Khi nào nên tách một field JSON thành cột thật?
4. Vì sao index đúng kỹ thuật vẫn có thể làm query chậm hơn?

## Key Takeaways

- GIN phục vụ containment / existence (`@>`, `?`), không phục vụ `->> =`.
- jsonb_path_ops nhỏ hơn nhưng chỉ cho `@>`.
- Index chỉ có lợi khi selectivity đủ thấp; luôn đo, đừng giả định.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`02b_strategy_b.sql`](02b_strategy_b.sql) | Strategy B |
| [`02c_strategy_c.sql`](02c_strategy_c.sql) | Strategy C |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
