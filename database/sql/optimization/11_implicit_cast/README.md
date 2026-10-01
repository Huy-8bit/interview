# Lab 11 · Implicit casts that disable an index

## Objective

Thấy **implicit cast** (so sánh khác kiểu dữ liệu) có thể ép PostgreSQL chuyển kiểu **cột** và bỏ qua index.

## Problem

Ba bug thường gặp từ ORM/driver: so sánh id `bigint` với literal `numeric` (`250000.0`), so sánh
`user_id::text` với chuỗi, bind tham số `char(n)` cho cột `varchar`. Câu SQL "trông đúng", trả về
đúng kết quả, nhưng mỗi câu quét 5 triệu dòng.

## Baseline Query

Q1 — bigint column compared with a numeric literal

```sql
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000.0;
```

Q2 — Casting the column to text to compare with a string

```sql
SELECT id, order_number, total_amount
FROM orders
WHERE user_id::text = '1144205';
```

Q3 — varchar column compared with a char(n) parameter

```sql
SELECT id, username
FROM users
WHERE phone = '+1-236-702-0729'::char(15);
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Gather  (cost=1000.00..234784.24 rows=25002 width=34) (actual time=138.360..140.478 rows=1 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   Buffers: shared hit=727 read=199305
   ->  Parallel Seq Scan on orders  (cost=0.00..231284.04 rows=10418 width=34) (actual time=91.314..130.007 rows=0 loops=3)
         Filter: ((orders.id)::numeric = 250000.0)
         Rows Removed by Filter: 1666666
         Buffers: shared hit=727 read=199305
 Planning Time: 0.047 ms
 Execution Time: 140.614 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Với `col = value` khác kiểu, PostgreSQL tìm một operator khớp hai kiểu. Không có `bigint = numeric`
được index B-tree trên bigint hỗ trợ, nên nó dùng `numeric = numeric` và chuyển **cột** sang numeric:

```text
Parallel Seq Scan on orders
  Filter: ((id)::numeric = 250000.0)      <- cast áp lên cột, từng dòng
```
Tương tự `((phone)::bpchar = '...'::character(15))`.

## Bottleneck

Seq Scan 5 triệu dòng cho lookup theo khóa chính / khóa ngoại.

## Optimization Strategy A

**Fix the types in the query (cast the VALUE, never the column)** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Index Scan using pk_orders on orders  (cost=0.43..2.65 rows=1 width=34) (actual time=0.002..0.002 rows=1 loops=1)
   Index Cond: (orders.id = 250000)
   Buffers: shared hit=4
 Planning Time: 0.008 ms
 Execution Time: 0.003 ms
```

Q1 `Index Scan using pk_orders`, Q2 `Index Scan using idx_orders_user_id`, Q3 so sánh trên cột trần.

## Why It Improved

Truyền giá trị đúng kiểu của cột (`id = 250000`, `user_id = 1144205`, phone là text/varchar):
điều kiện trở thành `Index Cond` → Index Scan, micro giây. Riêng Q3 vẫn Seq Scan, nhưng giờ chỉ vì
`phone` không có index (Lab 01) — một index trên phone giờ đã dùng được.

## Trade-offs

Không có chi phí: đây là sửa lỗi, không phải đánh đổi. Nên kiểm tra kiểu tham số mà driver/ORM gửi lên (ví dụ `pg_stat_statements` hoặc log).

## Optimization Strategy B

**See the type resolution: errors and quoted literals** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
SELECT pg_typeof(250000) AS int_literal, pg_typeof(250000.0) AS numeric_literal,
       pg_typeof('250000') AS untyped_literal;

DO $$
BEGIN
  PERFORM 1 FROM orders WHERE order_number = 250000;
EXCEPTION WHEN others THEN
  RAISE NOTICE 'expected error: %', SQLERRM;
END $$;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Index Scan using pk_orders on orders  (cost=0.43..2.65 rows=1 width=34) (actual time=0.001..0.002 rows=1 loops=1)
   Index Cond: (orders.id = '250000'::bigint)
   Buffers: shared hit=4
 Planning Time: 0.008 ms
 Execution Time: 0.003 ms
```

Literal **không có kiểu** (`'250000'`) nhận kiểu của cột → `Index Cond: (id = '250000'::bigint)` — an
toàn. Một số tổ hợp bị cấm hẳn (`order_number = 250000` → `operator does not exist: character varying = integer`):
lỗi rõ ràng còn hơn một Seq Scan âm thầm.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — bigint column compared with a numeric literal**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Seq Scan on public.orders` | 1 | 1,666,666 | shared hit=727 read=199305 | 140.6 ms |
| Strategy A | `Index Scan using pk_orders on public.orders` | 1 | 0 | shared hit=4 | 0.003 ms |

**Q2 — Casting the column to text to compare with a string**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Seq Scan on public.orders` | 5 | 1,666,665 | shared hit=1015 read=199017 | 158.3 ms |
| Strategy A | `Index Scan using idx_orders_user_id on public.orders` | 5 | 0 | shared hit=8 | 0.004 ms |

**Q3 — varchar column compared with a char(n) parameter**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Seq Scan on public.users` | 1 | 1,666,666 | shared hit=194 read=250006 | 157.3 ms |
| Strategy A | `Parallel Seq Scan on public.users` | 1 | 1,666,666 | shared hit=482 read=249718 | 157.1 ms |

**Strategy B — See the type resolution: errors and quoted literals**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Untyped string literal takes the column type (index used) | `Index Scan using pk_orders on public.orders` | 1 | 0 | shared hit=4 | 0.003 ms |

## Reset

```sql
-- (nothing to undo: query rewrite only)
-- (nothing to undo)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `::numeric`, `::text`, `::bpchar` áp lên **cột** trong `Filter`.
- Cast áp lên **giá trị** (`'250000'::bigint`) là vô hại.

## Interview Questions

1. Vì sao `WHERE id = 1.0` không dùng index trên id bigint?
2. Literal không có kiểu ('123') được xử lý thế nào?
3. Làm sao phát hiện implicit cast gây Seq Scan trên production?
4. Prepared statement với tham số sai kiểu ảnh hưởng plan ra sao?

## Key Takeaways

- Cast trên cột = index trên cột đó bị vô hiệu hoá cho điều kiện ấy.
- Luôn truyền tham số đúng kiểu của cột.
- Đọc Filter trong EXPLAIN để thấy cast ngầm — SQL nguồn không cho thấy nó.

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
