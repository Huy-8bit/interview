# Lab 05 · Composite index: filter + sort in one index

## Objective

Thiết kế **composite index** cho một query có cả điều kiện lọc và `ORDER BY ... LIMIT`, đi qua
từng bước: index một cột → index các cột lọc → index các cột lọc + cột sắp xếp.

## Problem

Trang danh mục hiển thị "20 sản phẩm đắt nhất đang bán" của một category; trang tài khoản hiển
thị "các đơn đã hoàn tất của tôi, mới nhất trước". Baseline có sẵn index một cột
(`idx_products_category_id`, `idx_products_price`, `idx_orders_user_id`) — bước 1 của lộ trình.

## Baseline Query

Q1 — Top 20 most expensive ACTIVE products of one category

```sql
SELECT id, name, price
FROM products
WHERE category_id = 37
  AND status = 'ACTIVE'
ORDER BY price DESC
LIMIT 20;
```

Q2 — The orders of one customer with a given status, newest first

```sql
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE user_id = 2215979
  AND status = 'COMPLETED'
ORDER BY created_at DESC;
```

## Expected Plan

Plan quan sát được (BEFORE). Q1 là cái bẫy kinh điển: planner chọn **Index Scan Backward trên
index giá** để khỏi phải sort, rồi lọc category/status từng dòng — Snacks là hàng rẻ nên nằm cuối
thứ tự giá, phải loại bỏ **2.35 triệu dòng** mới tìm đủ 20:

BEFORE — Q1:

```text
 Limit  (cost=0.43..250.75 rows=20 width=43) (actual time=5569.678..5570.858 rows=20 loops=1)
   Buffers: shared hit=263127 read=2079572
   ->  Index Scan Backward using idx_products_price on products  (actual time=5569.677..5570.856 rows=20 loops=1)
         Filter: ((products.category_id = 37) AND (products.status = 'ACTIVE'::product_status))
         Rows Removed by Filter: 2352937
         Buffers: shared hit=263127 read=2079572
 Planning Time: 0.063 ms
 Execution Time: 5570.870 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Limit (20)
  └── Index Scan Backward using idx_products_price    <- đi từ giá cao nhất xuống
        Filter: (category_id = 37 AND status = 'ACTIVE')
        Rows Removed by Filter: 2352937
```

1. Planner thấy `ORDER BY price DESC LIMIT 20` và một index sắp sẵn theo `price`.
2. Nó ước lượng: ~4% sản phẩm là Snacks ACTIVE, phân bố **đều** theo giá → chỉ cần đọc ~500
   entry là đủ 20 dòng. Ước lượng này dựa trên giả định độc lập giữa giá và category.
3. Thực tế giá và category **tương quan mạnh** (snack rẻ): index backward phải đi qua gần như
   toàn bộ sản phẩm đắt (điện tử, nội thất…) trước khi gặp snack đầu tiên.

Q2 (orders): `Index Scan using idx_orders_user_id` → `Filter: status` → `Sort` riêng.

## Bottleneck

Q1: `Rows Removed by Filter: 2352937`, ~2.3 triệu buffers, nhiều giây cho 20 dòng. Q2: một node
`Sort` và một `Filter` thừa (nhỏ vì mỗi user chỉ có ≤16 đơn, nhưng cùng một dạng vấn đề).

## Optimization Strategy A

**Indexes on (category_id, status) and (user_id, status)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab05_products_cat_status ON products (category_id, status);
CREATE INDEX ix_lab05_orders_user_status  ON orders (user_id, status);
ANALYZE products, orders;
```

## Result

AFTER Strategy A — Q1:

```text
 Limit  (cost=0.43..253.81 rows=20 width=43) (actual time=6493.768..6495.033 rows=20 loops=1)
   Buffers: shared hit=263127 read=2079572
   ->  Index Scan Backward using idx_products_price on products  (actual time=6493.767..6495.030 rows=20 loops=1)
         Filter: ((products.category_id = 37) AND (products.status = 'ACTIVE'::product_status))
         Rows Removed by Filter: 2352937
         Buffers: shared hit=263127 read=2079572
 Planning Time: 0.153 ms
 Execution Time: 6495.056 ms
```

Q1 **không đổi** (vẫn Index Scan Backward trên `idx_products_price`, vẫn loại 2.35 triệu dòng).
Q2 dùng index mới nên mất `Filter`, nhưng vẫn còn `Sort`.

## Why It Improved

Strategy A (`(category_id, status)`) **không cứu được Q1**: planner vẫn đánh giá Index Scan
Backward trên giá rẻ hơn (vẫn giả định phân bố đều), nên plan và thời gian gần như y hệt. Đây là
bài học quan trọng: thêm đúng cột lọc vào index chưa đủ khi query còn ORDER BY + LIMIT.

Strategy B (`(category_id, status, price DESC)`): các entry của category 37 / ACTIVE nằm liền
nhau **và đã sắp theo giá giảm dần** → đọc đúng 20 entry đầu tiên rồi dừng. Không Filter, không
Sort, ~20 buffers, thời gian từ vài giây xuống micro giây. Q2 tương tự với
`(user_id, status, created_at DESC)`: biến mất cả node Sort.

## Trade-offs

- Hai index 3 cột: ~151 MB (products) và ~193 MB (orders) — so với lợi ích cho một màn hình cụ thể.
- Index B có cột đầu trùng `idx_products_category_id` / `idx_orders_user_id` → index cũ thành
  thừa, nên xem xét drop để không trả chi phí ghi hai lần.
- Index chỉ tối ưu đúng thứ tự `price DESC`; ORDER BY price ASC vẫn dùng được (đọc ngược), nhưng
  ORDER BY name thì không.

## Optimization Strategy B

**Indexes on (category_id, status, price DESC) and (user_id, status, created_at DESC)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab05_products_cat_status_price ON products (category_id, status, price DESC);
CREATE INDEX ix_lab05_orders_user_status_created ON orders (user_id, status, created_at DESC);
ANALYZE products, orders;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Limit  (cost=0.43..16.08 rows=20 width=43) (actual time=0.002..0.006 rows=20 loops=1)
   Buffers: shared hit=23
   ->  Index Scan using ix_lab05_products_cat_status_price on products  (actual time=0.002..0.005 rows=20 loops=1)
         Index Cond: ((products.category_id = 37) AND (products.status = 'ACTIVE'::product_status))
         Buffers: shared hit=23
 Planning Time: 0.013 ms
 Execution Time: 0.008 ms
```

Q1 và Q2 đều thành một Index Scan duy nhất trả về đúng số dòng cần, không Filter, không Sort.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Top 20 most expensive ACTIVE products of one category**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan Backward using idx_products_price on public.products` | 20 | 2,352,937 | shared hit=263127 read=2079572 | 5,570.9 ms |
| Strategy A | `Index Scan Backward using idx_products_price on public.products` | 20 | 2,352,937 | shared hit=263127 read=2079572 | 6,495.1 ms |
| Strategy B | `Index Scan using ix_lab05_products_cat_status_price on public.products` | 20 | 0 | shared hit=23 | 0.008 ms |

**Q2 — The orders of one customer with a given status, newest first**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Index Scan using idx_orders_user_id on public.orders` | 10 | 6 | shared hit=19 | 0.018 ms |
| Strategy A | `Index Scan using ix_lab05_orders_user_status on public.orders` | 10 | 0 | shared hit=13 | 0.009 ms |
| Strategy B | `Index Scan using ix_lab05_orders_user_status_created on public.orders` | 10 | 0 | shared hit=13 | 0.006 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab05_products_cat_status;
DROP INDEX IF EXISTS ix_lab05_orders_user_status;
DROP INDEX IF EXISTS ix_lab05_products_cat_status_price;
DROP INDEX IF EXISTS ix_lab05_orders_user_status_created;
ANALYZE products, orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Index Scan Backward` + `Filter` + `Rows Removed by Filter` lớn dưới một `Limit`: dấu hiệu
  planner đặt cược vào phân bố đều và thua.
- `Index Cond` chứa những cột nào (dùng để seek) — cột nào chỉ còn ở `Filter`.
- Có hay không node `Sort` giữa Limit và scan.
- `cost` của node Limit nhỏ (planner tưởng rẻ) nhưng `actual time` lớn: ước lượng sai.

## Interview Questions

1. Thứ tự cột trong composite index cho query `WHERE a = ? AND b = ? ORDER BY c DESC LIMIT n` nên là gì? Vì sao?
2. Vì sao planner lại chọn index trên cột ORDER BY thay vì index trên cột WHERE? Khi nào lựa chọn đó sai?
3. Index (a, b, c) có phục vụ được `WHERE a = ? ORDER BY c` không?
4. Làm sao phát hiện tương quan giữa hai cột gây ước lượng sai cho LIMIT?
5. Khi tạo index (a, b, c), index (a) có còn cần thiết không?

## Key Takeaways

- Composite index cho filter + sort: các cột so sánh bằng trước, cột ORDER BY sau, đúng chiều sắp xếp.
- Chỉ đưa cột lọc vào index là chưa đủ nếu planner vẫn thích một index khác để tránh Sort.
- LIMIT làm planner tối ưu cho 'dòng đầu tiên': khi dữ liệu tương quan, ước lượng đó có thể sai rất nặng.
- Mỗi composite index mới thường làm một index cũ trở nên thừa — hãy dọn dẹp.

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
