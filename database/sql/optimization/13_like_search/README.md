# Lab 13 · LIKE 'prefix%' vs ILIKE '%contains%': pattern ops vs trigram

## Objective

Tìm kiếm chuỗi: `LIKE 'prefix%'` với `varchar_pattern_ops` và `ILIKE '%contains%'` với trigram (`pg_trgm`).

## Problem

Ô tìm kiếm sản phẩm: tìm theo đầu tên ("Sony Pro…") và tìm chứa ("air fryer"). Database dùng
collation `en_US.utf8`, cột `name` không có index.

## Baseline Query

Q1 — Prefix search: names starting with 'Sony Pro'

```sql
SELECT count(*)
FROM products
WHERE name LIKE 'Sony Pro%';
```

Q2 — Contains search: names containing 'air fryer' (case-insensitive)

```sql
SELECT count(*)
FROM products
WHERE name ILIKE '%air fryer%';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=288599.76..288599.77 rows=1 width=8) (actual time=137.447..139.527 rows=1 loops=1)
   Buffers: shared hit=288 read=261267
   ->  Gather  (cost=288599.54..288599.75 rows=2 width=8) (actual time=137.370..139.519 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=288 read=261267
         ->  Partial Aggregate  (cost=287599.54..287599.55 rows=1 width=8) (actual time=127.891..127.891 rows=1 loops=3)
               Buffers: shared hit=288 read=261267
               ->  Parallel Seq Scan on products  (cost=0.00..287599.02 rows=208 width=0) (actual time=2.437..127.824 rows=559 loops=3)
                     Filter: ((products.name)::text ~~ 'Sony Pro%'::text)
                     Rows Removed by Filter: 1666108
                     Buffers: shared hit=288 read=261267
 Planning Time: 0.070 ms
 Execution Time: 139.718 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

- B-tree thường dưới collation không phải `C` **không** phục vụ được `LIKE 'prefix%'` (thứ tự
  ngôn ngữ ≠ thứ tự byte). `varchar_pattern_ops` so sánh từng byte nên biến prefix thành range:
  `name ~>=~ 'Sony Pro' AND name ~<~ 'Sony Prp'`.
- `%` ở đầu nghĩa là "bắt đầu ở đâu cũng được": không B-tree nào giúp được. `pg_trgm` tách chuỗi
  thành các bộ 3 ký tự, GIN tìm các dòng chứa đủ mọi trigram của pattern, rồi recheck.

## Bottleneck

Seq Scan ~261k trang products; với ILIKE còn tốn CPU (~750 ms).

## Optimization Strategy A

**B-tree (name varchar_pattern_ops)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab13_products_name_pattern ON products (name varchar_pattern_ops);
```

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=2.93..2.94 rows=1 width=8) (actual time=0.203..0.203 rows=1 loops=1)
   Buffers: shared hit=1367
   ->  Index Only Scan using ix_lab13_products_name_pattern on products  (actual time=0.004..0.168 rows=1676 loops=1)
         Index Cond: ((products.name ~>=~ 'Sony Pro'::text) AND (products.name ~<~ 'Sony Prp'::text))
         Filter: ((products.name)::text ~~ 'Sony Pro%'::text)
         Heap Fetches: 0
         Buffers: shared hit=1367
 Planning Time: 0.029 ms
 Execution Time: 0.206 ms
```

Prefix: Index Only Scan siêu nhanh. Contains: index bị quét toàn bộ, không có lợi.

## Why It Improved

- Prefix + `varchar_pattern_ops`: Index Only Scan trên đúng đoạn tên, ~0.2 ms.
- Contains + trigram: Bitmap Index Scan → ~185 ms thay vì ~750 ms (28k dòng khớp phải đọc từ heap).

## Trade-offs

- Quan sát thật: với `varchar_pattern_ops`, planner dùng index cho cả câu `ILIKE '%air fryer%'` — **quét
  toàn bộ index** (3.7 triệu buffers) mà không nhanh hơn Seq Scan. Index dùng được không có nghĩa là hữu ích.
- Trigram index ~283 MB (gấp đôi pattern index 144 MB) và cập nhật chậm hơn.
- Trigram cho prefix chậm hơn pattern_ops ~100 lần (24 ms vs 0.2 ms): phải xử lý nhiều trigram + recheck.
- Pattern dưới 3 ký tự (ví dụ `'%ab%'`) không tạo được trigram đầy đủ → index kém hiệu quả.

## Optimization Strategy B

**GIN (name gin_trgm_ops) - pg_trgm (extension already installed)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab13_products_name_trgm ON products USING gin (name gin_trgm_ops);
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=721.91..721.92 rows=1 width=8) (actual time=23.867..23.868 rows=1 loops=1)
   Buffers: shared hit=3395
   ->  Bitmap Heap Scan on products  (cost=166.60..720.66 rows=500 width=0) (actual time=22.254..23.791 rows=1676 loops=1)
         Recheck Cond: ((products.name)::text ~~ 'Sony Pro%'::text)
         Heap Blocks: exact=1667
         Buffers: shared hit=3395
         ->  Bitmap Index Scan on ix_lab13_products_name_trgm  (actual time=22.127..22.128 rows=1676 loops=1)
               Index Cond: ((products.name)::text ~~ 'Sony Pro%'::text)
               Buffers: shared hit=1728
   Buffers: shared hit=1
 Planning Time: 0.159 ms
 Execution Time: 23.904 ms
```

Cả prefix và contains đều dùng Bitmap Index Scan trên trigram; contains nhanh hơn ~4 lần, prefix chậm hơn Strategy A.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Prefix search: names starting with 'Sony Pro'**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.products` | 1 | 1,666,108 | shared hit=288 read=261267 | 139.7 ms |
| Strategy A | `Index Only Scan using ix_lab13_products_name_pattern on public.products` | 1 | 0 | shared hit=1367 | 0.206 ms |
| Strategy B | `Bitmap Heap Scan on public.products, Bitmap Index Scan on ix_lab13_products_name_trgm` | 1 | 0 | shared hit=3395 | 23.9 ms |

**Q2 — Contains search: names containing 'air fryer' (case-insensitive)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.products` | 1 | 1,657,319 | shared hit=576 read=260979 | 749.3 ms |
| Strategy A | `Partial Aggregate, Parallel Index Only Scan using ix_lab13_products_name_pattern on public.products` | 1 | 1,657,319 | shared hit=3710525 | 730.7 ms |
| Strategy B | `Bitmap Heap Scan on public.products, Bitmap Index Scan on ix_lab13_products_name_trgm` | 1 | 0 | shared hit=27021 | 184.8 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab13_products_name_pattern;
DROP INDEX IF EXISTS ix_lab13_products_name_trgm;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Index Cond: ((name ~>=~ ...) AND (name ~<~ ...))`: prefix được chuyển thành range.
- Index Only Scan **không có Index Cond** + `Filter`: quét toàn bộ index.
- Trigram: `Recheck Cond` + `Heap Blocks` = số dòng ứng viên phải kiểm tra.

## Interview Questions

1. Vì sao B-tree thường không phục vụ `LIKE 'abc%'` dưới collation en_US?
2. text_pattern_ops / varchar_pattern_ops là gì?
3. pg_trgm hoạt động thế nào? Vì sao pattern ngắn hơn 3 ký tự kém hiệu quả?
4. Khi nào cần full-text search (tsvector) thay vì trigram?

## Key Takeaways

- Prefix search: B-tree pattern_ops (hoặc collation C).
- Contains / ILIKE / fuzzy: pg_trgm GIN (hoặc GiST).
- Một index 'được dùng' có thể vẫn quét toàn bộ — kiểm tra Index Cond và Buffers.

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
