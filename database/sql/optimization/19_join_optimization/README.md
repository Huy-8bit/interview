# Lab 19 · Join optimization: the unindexed foreign key

## Objective

Thấy tác động của **foreign key không có index** lên JOIN và lên DELETE ở bảng cha; tối ưu bằng index (đầy đủ hoặc partial).

## Problem

`reviews.order_id` là FOREIGN KEY tới `orders` (ON DELETE SET NULL) nhưng **không có index** (cố ý,
xem `04-indexes.sql`). Câu hỏi "review của các đơn trong một ngày" và thao tác xoá một đơn hàng đều
phải quét 5 triệu review.

## Baseline Query

Q1 — Reviews of the orders placed on one day

```sql
SELECT o.order_number, r.rating, r.title
FROM orders o
JOIN reviews r ON r.order_id = o.id
WHERE o.created_at >= '2025-06-01'
  AND o.created_at <  '2025-06-02';
```

Q2 — Delete one order (FK ON DELETE SET NULL must find its reviews)

```sql
DELETE FROM orders WHERE id = 250001;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Gather  (cost=1121.28..132743.39 rows=1577 width=40) (actual time=34.756..165.419 rows=2398 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   Buffers: shared hit=613 read=104840
   ->  Hash Join  (cost=121.28..131585.69 rows=657 width=40) (actual time=28.127..156.711 rows=799 loops=3)
         Inner Unique: true
         Hash Cond: (r.order_id = o.id)
         Buffers: shared hit=613 read=104840
         ->  Parallel Seq Scan on reviews r  (cost=0.00..125995.18 rows=2083518 width=28) (actual time=0.010..80.109 rows=1666667 loops=3)
               Buffers: shared hit=320 read=104840
         ->  Hash  (cost=101.57..101.57 rows=1577 width=28) (actual time=4.148..4.148 rows=1737 loops=3)
               Buckets: 2048  Batches: 1  Memory Usage: 125kB
               Buffers: shared hit=233
               ->  Index Scan using idx_orders_created_at on orders o  (actual time=3.756..4.058 rows=1737 loops=3)
                     Index Cond: ((o.created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone) AND (o.created_at < '2025-06-02 00:00 ...
                     Buffers: shared hit=233
   Buffers: shared hit=4
 Planning Time: 0.115 ms
 Execution Time: 165.703 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Gather
  └── Hash Join   Hash Cond: (r.order_id = o.id)
        ├── Parallel Seq Scan on reviews r     <- 5M dòng, để tìm ~2,400 review
        └── Hash
              └── Index Scan using idx_orders_created_at on orders o   (~5k đơn của ngày)
```
DELETE trên `orders` kích hoạt trigger nội bộ của mỗi FK: `fk_reviews_order` phải chạy
`UPDATE reviews SET order_id = NULL WHERE order_id = $1` — không index → Seq Scan reviews.
Chi phí đó **không nằm trong cây plan** mà ở dòng `Trigger for constraint ...` và trong Execution Time.

## Bottleneck

Q1 quét toàn bộ reviews (~165 ms). Q2 (DELETE 1 đơn) mất hàng trăm ms gần như toàn bộ cho trigger FK.

## Optimization Strategy A

**Index the foreign key column: reviews(order_id)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab19_reviews_order_id ON reviews (order_id);
ANALYZE reviews;
```

## Result

AFTER Strategy A — Q1:

```text
 Nested Loop  (cost=0.86..4212.81 rows=1576 width=39) (actual time=0.006..1.410 rows=2398 loops=1)
   Buffers: shared hit=7686
   ->  Index Scan using idx_orders_created_at on orders o  (actual time=0.005..0.095 rows=1737 loops=1)
         Index Cond: ((o.created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone) AND (o.created_at < '2025-06-02 00:00:00+00'::tim ...
         Buffers: shared hit=77
   ->  Index Scan using ix_lab19_reviews_order_id on reviews r  (actual time=0.000..0.001 rows=1 loops=1737)
         Index Cond: (r.order_id = o.id)
         Buffers: shared hit=7609
   Buffers: shared hit=12
 Planning Time: 0.045 ms
 Execution Time: 1.451 ms
```

Q1 `Nested Loop` + `Index Scan using ix_lab19_reviews_order_id`; Q2 DELETE nhanh hơn ~100 lần.

## Why It Improved

Index trên `reviews(order_id)`: Q1 thành **Nested Loop** (5k lookup index) ~1.5 ms; DELETE 1 đơn còn ~2 ms
(trigger FK dùng index). Đó là lý do quy tắc "index mọi cột FK của bảng con *nếu* bảng cha bị
DELETE/UPDATE khóa hoặc có JOIN theo cột đó".

## Trade-offs

- Index đầy đủ ~76 MB; mỗi INSERT review cập nhật thêm một index.
- `inventory.warehouse_id` cũng là FK không index nhưng **không cần**: chỉ 5 kho, không bao giờ xoá kho,
  mỗi giá trị khớp 20% bảng — index không giúp được gì.

## Optimization Strategy B

**Partial index reviews(order_id) WHERE order_id IS NOT NULL** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab19_reviews_order_id_nn ON reviews (order_id) WHERE order_id IS NOT NULL;
ANALYZE reviews;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Nested Loop  (cost=0.86..4195.03 rows=1577 width=40) (actual time=0.006..1.571 rows=2398 loops=1)
   Buffers: shared hit=7686
   ->  Index Scan using idx_orders_created_at on orders o  (actual time=0.005..0.107 rows=1737 loops=1)
         Index Cond: ((o.created_at >= '2025-06-01 00:00:00+00'::timestamp with time zone) AND (o.created_at < '2025-06-02 00:00:00+00'::tim ...
         Buffers: shared hit=77
   ->  Index Scan using ix_lab19_reviews_order_id_nn on reviews r  (actual time=0.001..0.001 rows=1 loops=1737)
         Index Cond: (r.order_id = o.id)
         Buffers: shared hit=7609
   Buffers: shared hit=4
 Planning Time: 0.041 ms
 Execution Time: 1.618 ms
```

Partial index `WHERE order_id IS NOT NULL` (~68 MB, bỏ ~25% review không gắn đơn) cho đúng các plan như A:
cả `r.order_id = o.id` lẫn điều kiện `order_id = $1` của trigger đều suy ra được `order_id IS NOT NULL`.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Reviews of the orders placed on one day**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Hash Join, Parallel Seq Scan on public.reviews r, Index Scan using idx_orders_created_at on public.orders o` | 2398 | 0 | shared hit=613 read=104840 | 165.7 ms |
| Strategy A | `Index Scan using idx_orders_created_at on public.orders o, Index Scan using ix_lab19_reviews_order_id on public.reviews ` | 2398 | 0 | shared hit=7686 | 1.451 ms |
| Strategy B | `Index Scan using idx_orders_created_at on public.orders o, Index Scan using ix_lab19_reviews_order_id_nn on public.revie` | 2398 | 0 | shared hit=7686 | 1.618 ms |

**Q2 — Delete one order (FK ON DELETE SET NULL must find its reviews)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using pk_orders on public.orders` | 0 | 0 | shared hit=13 read=3 dirtied=2 · WAL records=1 fpi=1 bytes=8039 | 230.9 ms |
| Strategy A | `Index Scan using pk_orders on public.orders` | 0 | 0 | shared hit=16 · WAL records=1 bytes=54 | 1.821 ms |
| Strategy B | `Index Scan using pk_orders on public.orders` | 0 | 0 | shared hit=16 · WAL records=1 bytes=54 | 0.413 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab19_reviews_order_id;
DROP INDEX IF EXISTS ix_lab19_reviews_order_id_nn;
ANALYZE reviews;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Seq Scan bảng con lớn bên trong một join chỉ trả ít dòng.
- Với DML: `Trigger for constraint <fk>: time=... calls=...` trong EXPLAIN ANALYZE.
- Query tìm FK thiếu index: [`docs/index-lab.md` §10](../../../docs/index-lab.md).

## Interview Questions

1. PostgreSQL có tự tạo index cho foreign key không?
2. Vì sao FK không index làm DELETE ở bảng cha chậm?
3. Chi phí kiểm tra FK hiện ở đâu trong EXPLAIN ANALYZE?
4. Có phải mọi FK đều cần index không?

## Key Takeaways

- PostgreSQL index cột được tham chiếu (PK/UNIQUE), không index cột tham chiếu (FK) ở bảng con.
- FK không index = Seq Scan bảng con cho mỗi DELETE/UPDATE khóa ở bảng cha.
- Partial index trên FK nullable: nhỏ hơn, vẫn phục vụ join và trigger.

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
