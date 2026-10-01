# Lab 07 · Covering index: INCLUDE vs composite key

## Objective

Dùng **covering index** để biến query thành Index Only Scan; so sánh `INCLUDE` với việc đưa cột
vào key; thấy chi phí dung lượng thật sự (B-tree deduplication).

## Problem

Thống kê bán hàng của sản phẩm bán chạy nhất (`product_id = 4905450`, ~34k dòng order_items).
Index `idx_order_items_product_id` tìm dòng rất nhanh, nhưng sau đó phải đọc heap để lấy
`quantity`, `unit_price` — và 34k dòng nằm trên ~29k trang heap khác nhau.

## Baseline Query

Q1 — Units sold and revenue of one product

```sql
SELECT count(*) AS lines, sum(quantity) AS units, round(avg(unit_price), 2) AS avg_price
FROM order_items
WHERE product_id = 4905450;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Aggregate  (cost=31600.33..31600.34 rows=1 width=48) (actual time=23.747..23.747 rows=1 loops=1)
   Buffers: shared hit=28988
   ->  Bitmap Heap Scan on order_items  (cost=314.27..31340.26 rows=34675 width=10) (actual time=4.341..21.386 rows=34485 loops=1)
         Recheck Cond: (order_items.product_id = 4905450)
         Heap Blocks: exact=28956
         Buffers: shared hit=28988
         ->  Bitmap Index Scan on idx_order_items_product_id  (actual time=1.803..1.804 rows=34485 loops=1)
               Index Cond: (order_items.product_id = 4905450)
               Buffers: shared hit=32
 Planning Time: 0.052 ms
 Execution Time: 23.767 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Aggregate
  └── Bitmap Heap Scan on order_items        <- ~29k trang heap (1 trang / dòng)
        └── Bitmap Index Scan on idx_order_items_product_id   <- ~32 trang index
```

Index trả TID rất rẻ; phần đắt là đi lấy cột không có trong index. Sau khi có covering index:

```text
Aggregate
  └── Index Only Scan using ix_lab07_items_product_incl   Heap Fetches: 0
```

## Bottleneck

`Heap Blocks: exact=28956`: hầu như mỗi dòng một lần đọc trang heap.

## Optimization Strategy A

**(product_id) INCLUDE (quantity, unit_price)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab07_items_product_incl ON order_items (product_id) INCLUDE (quantity, unit_price);
VACUUM (ANALYZE) order_items;   -- refresh the visibility map for Index Only Scans
```

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=1158.59..1158.60 rows=1 width=48) (actual time=2.833..2.833 rows=1 loops=1)
   Buffers: shared hit=177
   ->  Index Only Scan using ix_lab07_items_product_incl on order_items  (actual time=0.003..1.428 rows=34485 loops=1)
         Index Cond: (order_items.product_id = 4905450)
         Heap Fetches: 0
         Buffers: shared hit=177
 Planning Time: 0.019 ms
 Execution Time: 2.840 ms
```

`Index Only Scan using ix_lab07_items_product_incl`, Heap Fetches 0, ~180 buffers.

## Why It Improved

Mọi cột cần (product_id, quantity, unit_price) có trong index, visibility map đã set (VACUUM) →
không đọc heap: Buffers từ ~29k xuống ~180, thời gian giảm ~10 lần.

## Trade-offs

- Dung lượng: index covering ~**387 MB** so với **92 MB** của `idx_order_items_product_id`, tức to
  hơn 4 lần chứ không phải "thêm vài byte mỗi dòng". Lý do: từ PG13, B-tree **deduplication** gộp
  các entry có cùng key (mỗi product_id lặp lại trung bình ~3 lần, sản phẩm phổ biến hàng chục
  nghìn lần) thành một entry + danh sách TID. Có cột INCLUDE (hoặc thêm key) thì không gộp được.
- Mỗi INSERT/UPDATE quantity, unit_price phải cập nhật index lớn hơn.
- Index Only Scan chỉ hiệu quả khi bảng được VACUUM đều (Lab 04).

## Optimization Strategy B

**(product_id, quantity, unit_price) as key columns** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab07_items_product_qty_price ON order_items (product_id, quantity, unit_price);
VACUUM (ANALYZE) order_items;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=1219.59..1219.60 rows=1 width=48) (actual time=2.696..2.697 rows=1 loops=1)
   Buffers: shared hit=189
   ->  Index Only Scan using ix_lab07_items_product_qty_price on order_items  (actual time=0.008..1.412 rows=34485 loops=1)
         Index Cond: (order_items.product_id = 4905450)
         Heap Fetches: 0
         Buffers: shared hit=189
 Planning Time: 0.057 ms
 Execution Time: 2.710 ms
```

`(product_id, quantity, unit_price)` cho cùng plan, cùng số buffers, cùng kích thước (~388 MB).
Khác biệt: key columns được sắp xếp và tìm kiếm được (ví dụ `WHERE product_id = ? AND quantity > 3`
hoặc `ORDER BY product_id, quantity`), còn INCLUDE thì không; ngược lại INCLUDE cho phép thêm cột
vào một **UNIQUE** index mà không đổi ràng buộc unique và chấp nhận kiểu dữ liệu không có B-tree operator.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Units sold and revenue of one product**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Bitmap Heap Scan on public.order_items, Bitmap Index Scan on idx_order_items_product_id` | 1 | 0 | shared hit=28988 | 23.8 ms |
| Strategy A | `Index Only Scan using ix_lab07_items_product_incl on public.order_items` | 1 | 0 | shared hit=177 | 2.840 ms |
| Strategy B | `Index Only Scan using ix_lab07_items_product_qty_price on public.order_items` | 1 | 0 | shared hit=189 | 2.710 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab07_items_product_incl;
DROP INDEX IF EXISTS ix_lab07_items_product_qty_price;
ANALYZE order_items;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Bitmap Heap Scan` / `Index Scan` có `Heap Blocks` hoặc Buffers lớn hơn nhiều số trang index.
- Sau tối ưu: `Index Only Scan` và `Heap Fetches: 0`.
- Kích thước index (`pg_relation_size`) — thứ EXPLAIN không cho thấy.

## Interview Questions

1. Covering index là gì? INCLUDE khác gì key column?
2. Khi nào bắt buộc phải dùng INCLUDE thay vì thêm cột vào key?
3. B-tree deduplication là gì, và vì sao covering index thường lớn hơn nhiều so với dự kiến?
4. Index Only Scan cần điều kiện gì để không đọc heap?

## Key Takeaways

- Đọc heap cho từng dòng là chi phí ẩn lớn nhất của một index scan trả nhiều dòng rải rác.
- Covering index loại bỏ chi phí đó — nhưng có thể làm index to gấp nhiều lần vì mất deduplication.
- INCLUDE: payload không sắp xếp; key: sắp xếp và tìm kiếm được.

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
