# Lời giải bài tập SQL

Đề bài: [sql-exercises.md](sql-exercises.md). Thường có nhiều lời giải đúng; ở đây ưu tiên cách rõ ràng và hiệu quả.
Con số trong comment là ví dụ từ dataset mặc định (`SEED=42`) — của bạn có thể lệch một chút.

> Mọi khối SQL không có nhãn 👥 trong file này đã được chạy thử tự động trên dataset mặc định.

---

## Level 1 — Basic SQL

### 1.1

```sql
SELECT id, sku, name, brand, price
FROM products
WHERE status = 'ACTIVE'
ORDER BY price DESC
LIMIT 10;
```

`ORDER BY price DESC LIMIT 10` + index `idx_products_price` → planner đọc index **ngược** (`Index Scan Backward`) và dừng sau khi có đủ 10 dòng ACTIVE — không phải sort 100k dòng.

### 1.2

```sql
SELECT status,
       count(*)                                           AS users,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM users
GROUP BY status
ORDER BY users DESC;
```

`sum(count(*)) OVER ()` là window function chạy **sau** GROUP BY: tổng của các nhóm.

### 1.3

```sql
SELECT id, username, email, created_at
FROM users
WHERE created_at >= now() - interval '30 days'
ORDER BY created_at DESC;

SELECT count(*) FROM users WHERE created_at >= now() - interval '30 days';
```

`users.created_at` không có index → Seq Scan. Vì `id` tăng theo thời gian đăng ký, `ORDER BY id DESC` cho kết quả tương tự và dùng được PK.

### 1.4

```sql
SELECT id, name, price, cost,
       price - cost                                   AS margin,
       round(100 * (price - cost) / nullif(price, 0), 1) AS margin_pct
FROM products
WHERE brand = 'Apple' AND price < 500
ORDER BY price;
```

`nullif(price, 0)` tránh lỗi chia cho 0.

### 1.5

```sql
SELECT count(*) FROM users WHERE phone IS NULL;       -- ~15,000
SELECT count(*) FROM users WHERE phone = NULL;        -- 0
```

`NULL` nghĩa là "không biết". `phone = NULL` cho kết quả `NULL` (không phải `true`) với **mọi** dòng, và `WHERE` chỉ giữ dòng `true`. Luôn dùng `IS NULL` / `IS NOT NULL` / `IS DISTINCT FROM`.

### 1.6

```sql
-- a) JSONB: ->> trả text, -> trả jsonb
SELECT count(*) FROM users WHERE metadata->>'preferred_language' = 'vi';

-- b) mảng
SELECT id, name, tags FROM products WHERE 'bestseller' = ANY (tags) LIMIT 10;
-- tương đương, và dùng được GIN index trên tags nếu có:
SELECT id, name, tags FROM products WHERE tags @> ARRAY['bestseller'] LIMIT 10;

-- c) đường dẫn lồng nhau, ép kiểu
SELECT count(*)
FROM products
WHERE (attributes->'specs'->>'storage_gb')::int >= 512;
-- hoặc JSONPath:
SELECT count(*) FROM products WHERE attributes @@ '$.specs.storage_gb >= 512';
```

---

## Level 2 — JOIN

### 2.1

```sql
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at, u.username, u.email
FROM orders o
JOIN users u ON u.id = o.user_id
ORDER BY o.created_at DESC
LIMIT 10;
```

Plan: `Limit → Nested Loop → Index Scan Backward using idx_orders_created_at` + `Index Scan using pk_users` cho mỗi đơn. Nested Loop tối ưu khi vế ngoài rất ít dòng.

### 2.2

```sql
SELECT p.id, p.name,
       coalesce(parent.name || ' > ', '') || c.name AS category_path
FROM products p
JOIN categories c           ON c.id = p.category_id
LEFT JOIN categories parent ON parent.id = c.parent_id
ORDER BY p.id
LIMIT 20;
```

`LEFT JOIN` cho parent vì danh mục top-level có `parent_id IS NULL`.

### 2.3

```sql
SELECT count(*)
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
WHERE o.id IS NULL;

SELECT count(*)
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

Cả hai thường ra cùng plan **Hash Anti Join** (hoặc `Merge Anti Join`). **Tránh** `WHERE u.id NOT IN (SELECT user_id FROM orders)`: nếu subquery chứa một `NULL` thì kết quả luôn rỗng, và planner không chuyển được nó thành anti join.

### 2.4

```sql
SELECT p.name, oi.quantity, oi.unit_price, oi.discount, oi.total_price
FROM order_items oi
JOIN products p ON p.id = oi.product_id
WHERE oi.order_id = 250000
ORDER BY oi.id;

SELECT o.subtotal,
       (SELECT sum(total_price) FROM order_items WHERE order_id = o.id) AS sum_items,
       o.subtotal = (SELECT sum(total_price) FROM order_items WHERE order_id = o.id) AS ok
FROM orders o
WHERE o.id = 250000;
```

### 2.5

```sql
SELECT top.name AS top_category, count(*) AS never_sold
FROM products p
JOIN categories leaf ON leaf.id = p.category_id
JOIN categories top  ON top.id = leaf.parent_id
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.product_id = p.id)
GROUP BY top.name
ORDER BY never_sold DESC;
```

`NOT EXISTS` dùng `idx_order_items_product_id` (hoặc Hash Anti Join trên toàn bảng).

### 2.6

```sql
SELECT w.code, w.name,
       count(*) FILTER (WHERE i.quantity - i.reserved_quantity <= i.reorder_level) AS rows_to_restock,
       sum(i.quantity - i.reserved_quantity)                                        AS available_units
FROM warehouses w
JOIN inventory i ON i.warehouse_id = w.id
GROUP BY w.id, w.code, w.name
ORDER BY w.code;
```

Được `GROUP BY w.id` rồi chọn `w.name` mà không cần gộp nhóm theo `w.name`? Có — vì `w.id` là PK, PostgreSQL biết các cột khác phụ thuộc hàm vào nó. Ở đây liệt kê cho rõ.

---

## Level 3 — Aggregation

### 3.1

```sql
SELECT status,
       count(*)                     AS orders,
       sum(total_amount)            AS revenue,
       round(avg(total_amount), 2)  AS avg_order_value
FROM orders
GROUP BY status
ORDER BY status;          -- thứ tự khai báo của ENUM, không phải alphabet
```

### 3.2

```sql
SELECT date_trunc('month', created_at)::date AS month,
       count(*)                              AS orders,
       sum(total_amount)                     AS revenue
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1
ORDER BY 1;
```

Điều kiện dạng `created_at >= <hằng số>` (sargable) dùng được `idx_orders_status_created_at`.

### 3.3

```sql
SELECT p.id, p.name,
       sum(oi.quantity)    AS units_sold,
       sum(oi.total_price) AS revenue
FROM order_items oi
JOIN orders o   ON o.id = oi.order_id AND o.status <> 'CANCELLED'
JOIN products p ON p.id = oi.product_id
GROUP BY p.id, p.name
ORDER BY units_sold DESC
LIMIT 10;
```

Plan: `Hash Join` nhiều triệu dòng + `HashAggregate` (có thể song song: `Gather`, `Partial HashAggregate`, `Finalize`).

### 3.4

```sql
SELECT c.name,
       count(*)                                                         AS products,
       min(p.price), max(p.price),
       round(avg(p.price), 2)                                           AS avg_price,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY p.price)             AS median_price
FROM products p
JOIN categories c ON c.id = p.category_id
GROUP BY c.name
HAVING count(*) > 2000
ORDER BY products DESC;
```

`WHERE` lọc **dòng trước** khi gộp; `HAVING` lọc **nhóm sau** khi gộp. Median thấp hơn nhiều so với avg → phân phối giá lệch phải (nhiều hàng rẻ, ít hàng rất đắt).

### 3.5

```sql
SELECT payment_method,
       count(*)                               AS payments,
       sum(amount)                            AS total,
       round(avg(amount), 2)                  AS avg_amount,
       count(*) FILTER (WHERE amount > 500)   AS over_500
FROM payments
WHERE status = 'SUCCEEDED'
GROUP BY payment_method
ORDER BY total DESC;
```

### 3.6

```sql
SELECT p.id, p.name,
       count(*)                                                        AS reviews,
       round(avg(r.rating), 2)                                         AS avg_rating,
       round(100.0 * count(*) FILTER (WHERE r.rating = 5) / count(*), 1) AS pct_5_star,
       round(100.0 * count(*) FILTER (WHERE r.is_verified_purchase) / count(*), 1) AS pct_verified
FROM reviews r
JOIN products p ON p.id = r.product_id
GROUP BY p.id, p.name
HAVING count(*) >= 100 AND avg(r.rating) >= 4.3
ORDER BY avg_rating DESC, reviews DESC;
```

---

## Level 4 — Subquery / CTE

### 4.1

```sql
-- (A) correlated subquery - cách viết "tự nhiên" nhưng CỰC CHẬM ở đây (~100 giây!)
EXPLAIN
SELECT p.category_id, count(*) AS above_category_avg
FROM products p
WHERE p.status = 'ACTIVE'
  AND p.price > (SELECT avg(p2.price) FROM products p2 WHERE p2.category_id = p.category_id)
GROUP BY p.category_id;
--   Filter: ((status = 'ACTIVE') AND (price > (SubPlan 1)))
--   SubPlan 1 -> Aggregate -> Bitmap Heap Scan on products p2
-- SubPlan chạy lại cho TỪNG dòng ACTIVE (~85k lần), mỗi lần tính avg trên ~2,500 dòng
-- => ~200 triệu dòng được đọc. (Chỉ EXPLAIN; muốn tự thấy thì chạy với SET statement_timeout = '20s'.)

-- (B) window function: 1 lần duyệt, ~130 ms
SELECT category_id, count(*) AS above_category_avg
FROM (
  SELECT category_id, status, price, avg(price) OVER (PARTITION BY category_id) AS cat_avg
  FROM products
) t
WHERE status = 'ACTIVE' AND price > cat_avg
GROUP BY category_id
ORDER BY category_id;

-- (C) tính trung bình mỗi danh mục 1 lần rồi JOIN: ~40 ms (Hash Join, song song)
WITH cat AS (
  SELECT category_id, avg(price) AS avg_price FROM products GROUP BY category_id
)
SELECT p.category_id, count(*) AS above_category_avg
FROM products p
JOIN cat USING (category_id)
WHERE p.status = 'ACTIVE' AND p.price > cat.avg_price
GROUP BY p.category_id
ORDER BY p.category_id;
```

Bài học: correlated subquery trong `WHERE`/`SELECT` chạy **mỗi dòng một lần** (trừ khi planner chuyển được thành join hoặc dùng `Memoize`). Với 40 giá trị `category_id` khác nhau mà vẫn tính lại 85k lần là lãng phí thuần tuý — tính trước theo nhóm (B, C) nhanh hơn ~1000 lần. Cả ba cho cùng kết quả: trung bình tính trên **mọi** sản phẩm của danh mục (không chỉ ACTIVE).

### 4.2

```sql
WITH spend AS (
  SELECT user_id,
         count(*)          AS orders,
         sum(total_amount) AS total_spent,
         max(created_at)   AS last_order_at
  FROM orders
  WHERE status = 'COMPLETED'
  GROUP BY user_id
)
SELECT u.id, u.username, s.orders, s.total_spent, s.last_order_at
FROM spend s
JOIN users u ON u.id = s.user_id
WHERE s.total_spent > 5000
ORDER BY s.total_spent DESC;
```

Từ PostgreSQL 12, CTE không đệ quy, không có side effect và chỉ dùng 1 lần sẽ được *inline* (tối ưu như subquery). Muốn ép tính riêng: `WITH spend AS MATERIALIZED (...)`.

### 4.3

```sql
WITH purchases AS (
  SELECT DISTINCT o.user_id, c.name AS category
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.id
  JOIN products p     ON p.id = oi.product_id
  JOIN categories c   ON c.id = p.category_id
  WHERE o.status <> 'CANCELLED'
    AND c.name IN ('Laptops', 'Smartphones')
)
SELECT count(*)
FROM (
  SELECT user_id
  FROM purchases
  GROUP BY user_id
  HAVING count(DISTINCT category) = 2
) t;

-- cách khác: INTERSECT
SELECT count(*) FROM (
  SELECT o.user_id FROM orders o JOIN order_items oi ON oi.order_id = o.id
  JOIN products p ON p.id = oi.product_id JOIN categories c ON c.id = p.category_id
  WHERE o.status <> 'CANCELLED' AND c.name = 'Laptops'
  INTERSECT
  SELECT o.user_id FROM orders o JOIN order_items oi ON oi.order_id = o.id
  JOIN products p ON p.id = oi.product_id JOIN categories c ON c.id = p.category_id
  WHERE o.status <> 'CANCELLED' AND c.name = 'Smartphones'
) t;
```

### 4.4

```sql
WITH RECURSIVE tree AS (
  SELECT id, parent_id, name, name::text AS path, 1 AS depth
  FROM categories
  WHERE parent_id IS NULL                         -- anchor: gốc
  UNION ALL
  SELECT c.id, c.parent_id, c.name, t.path || ' > ' || c.name, t.depth + 1
  FROM categories c
  JOIN tree t ON c.parent_id = t.id               -- recursive: con của các node đã có
)
SELECT t.path, t.depth,
       (SELECT count(*) FROM products p WHERE p.category_id = t.id) AS direct_products
FROM tree t
ORDER BY t.path;
```

### 4.5

```sql
-- a)
SELECT count(*) AS bad_subtotal
FROM orders o
JOIN (SELECT order_id, sum(total_price) AS s FROM order_items GROUP BY order_id) oi ON oi.order_id = o.id
WHERE o.subtotal <> oi.s;

-- b)
SELECT count(*) AS bad_stock
FROM products p
LEFT JOIN (SELECT product_id, sum(quantity) AS q FROM inventory GROUP BY product_id) i ON i.product_id = p.id
WHERE p.stock_quantity IS DISTINCT FROM coalesce(i.q, 0);

-- c)
SELECT count(*) AS completed_without_payment
FROM orders o
WHERE o.status = 'COMPLETED'
  AND NOT EXISTS (SELECT 1 FROM payments pay WHERE pay.order_id = o.id AND pay.status = 'SUCCEEDED');
```

Tất cả phải ra `0`. Đây là loại truy vấn "data quality check" nên chạy định kỳ khi có dữ liệu *denormalized*.

### 4.6

```sql
WITH first_order AS (
  SELECT DISTINCT ON (user_id) user_id, id AS order_id, created_at, total_amount
  FROM orders
  ORDER BY user_id, created_at            -- DISTINCT ON giữ dòng ĐẦU TIÊN của mỗi user theo ORDER BY
)
SELECT date_trunc('month', created_at)::date AS cohort_month,
       count(*)                              AS new_customers,
       round(avg(total_amount), 2)           AS avg_first_order
FROM first_order
WHERE created_at >= date_trunc('month', now()) - interval '11 months'
GROUP BY 1
ORDER BY 1;
```

---

## Level 5 — Window Function

### 5.1

```sql
SELECT *
FROM (
  SELECT c.name AS category, p.name, p.price,
         row_number() OVER w AS rn,      -- 1,2,3,4 (luôn khác nhau)
         rank()       OVER w AS rnk,     -- 1,2,2,4 (bằng nhau cùng hạng, nhảy số)
         dense_rank() OVER w AS drnk     -- 1,2,2,3 (không nhảy số)
  FROM products p
  JOIN categories c ON c.id = p.category_id
  WHERE p.status = 'ACTIVE'
  WINDOW w AS (PARTITION BY p.category_id ORDER BY p.price DESC)
) t
WHERE rn <= 3
ORDER BY category, rn;
```

Không lọc trực tiếp `WHERE row_number() OVER ... <= 3` được vì window function tính **sau** WHERE → phải dùng subquery.

### 5.2

```sql
SELECT day,
       revenue,
       sum(revenue) OVER (ORDER BY day) AS running_total
FROM (
  SELECT created_at::date AS day, sum(total_amount) AS revenue
  FROM orders
  WHERE status = 'COMPLETED' AND created_at >= now() - interval '30 days'
  GROUP BY 1
) d
ORDER BY day;
```

### 5.3

```sql
SELECT id, order_number, status, total_amount, created_at,
       row_number() OVER (ORDER BY created_at)                          AS nth_order,
       created_at - lag(created_at) OVER (ORDER BY created_at)          AS since_previous,
       extract(day FROM created_at - lag(created_at) OVER (ORDER BY created_at))::int AS days_since_previous
FROM orders
WHERE user_id = 55368
ORDER BY created_at;
```

### 5.4

```sql
WITH monthly AS (
  SELECT date_trunc('month', created_at) AS month, sum(total_amount) AS revenue
  FROM orders
  WHERE status = 'COMPLETED'
    AND created_at >= date_trunc('month', now()) - interval '24 months'
  GROUP BY 1
)
SELECT month::date,
       revenue,
       lag(revenue) OVER (ORDER BY month) AS prev_month,
       round(100 * (revenue - lag(revenue) OVER (ORDER BY month))
                 / nullif(lag(revenue) OVER (ORDER BY month), 0), 1) AS mom_pct
FROM monthly
ORDER BY month;
```

Tháng hiện tại chưa hết nên thường "giảm mạnh"; tháng 11–12 tăng vọt (mùa Black Friday được mô phỏng trong dữ liệu).

### 5.5

```sql
WITH per_user AS (
  SELECT user_id, count(*) AS orders FROM orders GROUP BY user_id
),
bucketed AS (
  SELECT orders, ntile(5) OVER (ORDER BY orders DESC) AS quintile FROM per_user
)
SELECT quintile,
       count(*)                                            AS users,
       sum(orders)                                         AS orders,
       round(100.0 * sum(orders) / sum(sum(orders)) OVER (), 1) AS pct_of_orders
FROM bucketed
GROUP BY quintile
ORDER BY quintile;
-- nhóm 1 (20% user có nhiều đơn nhất) ~ 65-70% số đơn

WITH per_product AS (
  SELECT product_id, sum(quantity) AS units FROM order_items GROUP BY product_id
),
ranked AS (
  SELECT units, percent_rank() OVER (ORDER BY units DESC) AS pr FROM per_product
)
SELECT round(100.0 * sum(units) FILTER (WHERE pr < 0.01) / sum(units), 1) AS top_1pct_share,
       round(100.0 * sum(units) FILTER (WHERE pr < 0.20) / sum(units), 1) AS top_20pct_share
FROM ranked;
```

### 5.6

```sql
WITH daily AS (
  SELECT d::date AS day, count(o.id) AS orders
  FROM generate_series(current_date - 59, current_date, interval '1 day') AS d
  LEFT JOIN orders o ON o.created_at >= d AND o.created_at < d + interval '1 day'
  GROUP BY d
)
SELECT day, orders,
       round(avg(orders) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 1)  AS ma7_rows,
       round(avg(orders) OVER (ORDER BY day RANGE BETWEEN interval '6 days' PRECEDING AND CURRENT ROW), 1) AS ma7_range
FROM daily
ORDER BY day;
```

- `generate_series` + `LEFT JOIN` đảm bảo ngày không có đơn vẫn xuất hiện (với `count = 0`).
- `ROWS` đếm **số dòng** vật lý; `RANGE` dùng **giá trị** của cột ORDER BY. Nếu thiếu ngày (không dùng generate_series), `ROWS 6 PRECEDING` có thể trải dài hơn 7 ngày, còn `RANGE '6 days'` thì luôn đúng 7 ngày lịch.

---

## Level 6 — Index

### 6.1

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'ncunningham4242@gmail.com';
--  Seq Scan on users  Filter: ((email)::text = '...'::text)  Rows Removed by Filter: 99999

EXPLAIN ANALYZE SELECT * FROM users WHERE lower(email) = lower('ncunningham4242@gmail.com');
--  Index Scan using ux_users_email_lower on users  Index Cond: (lower((email)::text) = '...'::text)
```

Index biểu thức `lower(email)` chỉ khớp khi truy vấn dùng **đúng biểu thức** đó. Không nên thêm index trên `email` thô: ứng dụng nên luôn so khớp email không phân biệt hoa thường (email `Kimberly.scott1@Gmail.com` có trong dữ liệu!), index thứ hai tốn chỗ và làm chậm mọi INSERT/UPDATE. Lựa chọn khác: kiểu `citext`, hoặc lưu email đã chuẩn hoá lowercase.

### 6.2

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT id, username FROM users WHERE phone = '+1-378-604-4964';
-- Seq Scan ... Buffers: shared hit=... (≈ 3,000 pages)  ~ 15-30 ms

CREATE INDEX idx_users_phone ON users (phone);

EXPLAIN (ANALYZE, BUFFERS) SELECT id, username FROM users WHERE phone = '+1-378-604-4964';
-- Index Scan using idx_users_phone ... Buffers: shared hit=4  ~ 0.05 ms

SELECT pg_size_pretty(pg_relation_size('idx_users_phone'));   -- ~ 3-4 MB
-- DROP INDEX idx_users_phone;   -- nếu muốn làm lại
```

Buffers giảm từ hàng nghìn trang xuống ~4 (3 cấp B-tree + 1 trang heap).

### 6.3

```sql
-- a) cả hai cột: dùng tối ưu (Index Cond chứa cả status và created_at)
EXPLAIN SELECT count(*) FROM orders WHERE status = 'SHIPPED' AND created_at >= now() - interval '7 days';

-- b) chỉ created_at: planner chọn idx_orders_created_at (index khác), không phải index composite
EXPLAIN SELECT count(*) FROM orders WHERE created_at >= now() - interval '7 days';

-- c) chỉ status: vẫn dùng được idx_orders_status_created_at vì status là cột ĐẦU
EXPLAIN SELECT count(*) FROM orders WHERE status = 'PENDING';
-- nhưng với status phổ biến, Seq Scan rẻ hơn:
EXPLAIN SELECT count(*) FROM orders WHERE status = 'COMPLETED';
```

B-tree `(status, created_at)` được sắp theo status trước, trong cùng status mới theo created_at — giống danh bạ sắp theo (họ, tên): tra theo họ dễ, tra chỉ theo tên thì phải lật cả cuốn. Nếu xoá `idx_orders_created_at`, truy vấn b) chỉ còn cách *Seq Scan* (hoặc PostgreSQL 18+ có *skip scan*). Quy tắc chọn thứ tự cột: cột lọc bằng `=` trước, cột lọc theo khoảng / ORDER BY sau.

### 6.4

```sql
EXPLAIN ANALYZE
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'PENDING' AND created_at < now() - interval '1 day'
ORDER BY created_at
LIMIT 100;
-- Seq Scan on payments (≈ 513k dòng) + Sort

CREATE INDEX idx_payments_pending_created ON payments (created_at) WHERE status = 'PENDING';
CREATE INDEX idx_payments_status_created  ON payments (status, created_at);   -- để so sánh

SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_payments_pending_created', 'idx_payments_status_created');
-- partial ≈ vài trăm KB vs full ≈ 10+ MB

EXPLAIN ANALYZE
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'PENDING' AND created_at < now() - interval '1 day'
ORDER BY created_at
LIMIT 100;
-- Index Scan using idx_payments_pending_created

DROP INDEX idx_payments_status_created;
```

Partial index chỉ chứa dòng thoả `WHERE status = 'PENDING'` (~6% bảng) → nhỏ, nằm gọn trong cache, và không bị cập nhật khi các dòng khác thay đổi. Truy vấn phải có điều kiện **suy ra được** điều kiện của index.

### 6.5

```sql
-- chọn một sản phẩm bán chạy
SELECT product_id, count(*) FROM order_items GROUP BY 1 ORDER BY 2 DESC LIMIT 1;

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(quantity) FROM order_items WHERE product_id = 12345;   -- thay 12345
-- Bitmap Heap Scan: phải đọc heap để lấy quantity

CREATE INDEX idx_order_items_product_qty ON order_items (product_id) INCLUDE (quantity);
VACUUM (ANALYZE) order_items;          -- cập nhật visibility map

EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(quantity) FROM order_items WHERE product_id = 12345;
-- Index Only Scan using idx_order_items_product_qty ... Heap Fetches: 0
```

`INCLUDE` đặt `quantity` vào lá của index (không phải khoá tìm kiếm) → truy vấn trả lời chỉ từ index. `Heap Fetches: 0` nghĩa là mọi page đều được đánh dấu *all-visible* trong visibility map; sau nhiều UPDATE/DELETE mà chưa VACUUM, con số này tăng (xem bài 10.4). Index này thay thế được `idx_order_items_product_id` — xoá index cũ để không phải duy trì cả hai.

### 6.6

```sql
-- a) index là prefix của index khác trên cùng bảng
SELECT a.indrelid::regclass AS table_name,
       a.indexrelid::regclass AS redundant_index,
       b.indexrelid::regclass AS covered_by,
       pg_size_pretty(pg_relation_size(a.indexrelid)) AS wasted
FROM pg_index a
JOIN pg_index b ON a.indrelid = b.indrelid
               AND a.indexrelid <> b.indexrelid
               AND a.indnkeyatts <= b.indnkeyatts
               AND (b.indkey::int2[])[0:a.indnkeyatts - 1] = (a.indkey::int2[])[0:a.indnkeyatts - 1]
WHERE NOT a.indisunique
  AND a.indpred IS NULL AND b.indpred IS NULL
  AND a.indexprs IS NULL AND b.indexprs IS NULL;
-- idx_order_items_order_id  -> uq_order_items_order_product  (~33 MB)

-- b) foreign key không có index bắt đầu bằng các cột của FK
SELECT c.conrelid::regclass AS table_name,
       c.conname,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid
      AND (i.indkey::int2[])[0:cardinality(c.conkey) - 1] = c.conkey
  );
-- fk_inventory_warehouse, fk_reviews_order

-- chứng minh: DELETE một order phải quét toàn bộ reviews để SET NULL
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF)
DELETE FROM orders WHERE id = (SELECT order_id FROM reviews WHERE order_id IS NOT NULL LIMIT 1);
-- ...
-- Trigger for constraint fk_reviews_order: time=30.5 calls=1     <- Seq Scan 300k reviews
ROLLBACK;

CREATE INDEX idx_reviews_order_id ON reviews (order_id);
BEGIN;
EXPLAIN (ANALYZE, COSTS OFF)
DELETE FROM orders WHERE id = (SELECT order_id FROM reviews WHERE order_id IS NOT NULL LIMIT 1);
-- Trigger for constraint fk_reviews_order: time=0.1 calls=1
ROLLBACK;
```

PostgreSQL **không** tự tạo index cho cột FK (khác MySQL/InnoDB). Mỗi `DELETE`/`UPDATE` khoá chính ở bảng cha phải tìm dòng con — không có index là Seq Scan bảng con, và giữ lock lâu hơn.

---

## Level 7 — Query Optimization

### 7.1

Xem từng bước và output thật: [index-lab.md §3.1](index-lab.md#31-bài-tập-tối-ưu-truy-vấn-đơn-hàng-của-tôi). Tóm tắt:

```sql
CREATE INDEX idx_orders_user_status_created ON orders (user_id, status, created_at DESC);

EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 55368 AND status = 'COMPLETED' ORDER BY created_at DESC;
-- Index Scan using idx_orders_user_status_created  (không còn Filter, không còn Sort)

-- index mới bao trùm idx_orders_user_id (prefix) -> có thể bỏ index cũ
DROP INDEX idx_orders_user_status_created;   -- dọn lại cho các bài khác
```

### 7.2

```sql
-- OFFSET: phải đọc và vứt bỏ 100,000 dòng đầu
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_number, created_at FROM orders
ORDER BY created_at DESC, id DESC
OFFSET 99980 LIMIT 20;

-- KEYSET: nhớ (created_at, id) của dòng cuối trang trước, "tìm tiếp từ đó"
SELECT created_at, id FROM orders ORDER BY created_at DESC, id DESC OFFSET 99979 LIMIT 1;  -- lấy "con trỏ"

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_number, created_at FROM orders
WHERE (created_at, id) < ('2026-01-01 00:00:00+00', 400000)       -- thay bằng giá trị con trỏ ở trên
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

Để keyset dùng index tối ưu, cần index khớp **đúng** thứ tự sort: `CREATE INDEX ON orders (created_at DESC, id DESC);` (hoặc `(created_at, id)` — B-tree đọc ngược được). OFFSET càng sâu càng chậm (O(offset)); keyset luôn O(log n + page). Nhược điểm keyset: không nhảy thẳng tới "trang 5000".

### 7.3

```sql
EXPLAIN ANALYZE SELECT count(*) FROM orders WHERE created_at::date = current_date - 1;
-- Parallel Seq Scan: phải tính created_at::date cho mọi dòng

EXPLAIN ANALYZE SELECT count(*) FROM orders
WHERE created_at >= current_date - 1 AND created_at < current_date;
-- Index Only Scan using idx_orders_created_at
```

Bọc cột trong hàm/ép kiểu (`created_at::date`, `date_trunc(...)`, `extract(year FROM ...)`, `lower(col)`, `col + 1 = ...`) làm điều kiện **không sargable** — index sắp theo giá trị cột, không theo kết quả hàm. Viết lại thành khoảng trên cột gốc, hoặc tạo expression index nếu buộc phải dùng hàm. (Lưu ý: `current_date` phụ thuộc `timezone` của session.)

### 7.4

```sql
-- cần idx_users_phone từ bài 6.2
CREATE INDEX IF NOT EXISTS idx_users_phone ON users (phone);

EXPLAIN ANALYZE
SELECT id, username FROM users
WHERE lower(email) = 'ncunningham4242@gmail.com' OR phone = '+1-378-604-4964';
-- Bitmap Heap Scan
--   -> BitmapOr
--        -> Bitmap Index Scan on ux_users_email_lower
--        -> Bitmap Index Scan on idx_users_phone

EXPLAIN ANALYZE
SELECT id, username FROM users WHERE lower(email) = 'ncunningham4242@gmail.com'
UNION
SELECT id, username FROM users WHERE phone = '+1-378-604-4964';
```

Nếu **một** vế của `OR` không có index, cả truy vấn thành Seq Scan (thử `DROP INDEX idx_users_phone`). `UNION` (khử trùng lặp) hoặc `UNION ALL` + điều kiện loại trừ cho phép mỗi vế dùng plan riêng.

### 7.5

```sql
EXPLAIN ANALYZE SELECT count(*) FROM addresses WHERE country_code = 'VN' AND city = 'Hanoi';
-- rows=… (ước lượng rất nhỏ)  actual rows=…(lớn hơn nhiều lần)

CREATE STATISTICS st_addresses_country_city (dependencies, mcv) ON country_code, city FROM addresses;
ANALYZE addresses;

EXPLAIN ANALYZE SELECT count(*) FROM addresses WHERE country_code = 'VN' AND city = 'Hanoi';
-- ước lượng giờ sát thực tế

SELECT statistics_name, dependencies FROM pg_stats_ext WHERE statistics_name = 'st_addresses_country_city';
DROP STATISTICS st_addresses_country_city;
```

Mặc định planner coi các điều kiện **độc lập**: `sel(VN) × sel(Hanoi)`. Nhưng `city = 'Hanoi'` đã kéo theo `country_code = 'VN'` → nhân hai xác suất là đếm "trừ hai lần". Ước lượng sai số dòng là nguyên nhân số 1 của plan tồi (chọn Nested Loop cho hàng trăm nghìn dòng...).

### 7.6

```sql
SET work_mem = '4MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders ORDER BY total_amount DESC;
-- Sort Method: external merge  Disk: ~150000kB     temp read/written=...

SET work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders ORDER BY total_amount DESC;
-- Sort Method: quicksort  Memory: ~...kB

SET work_mem = '4MB';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders ORDER BY total_amount DESC LIMIT 100;
-- Sort Method: top-N heapsort  Memory: ~60kB

RESET work_mem;
```

`work_mem` là giới hạn **cho mỗi node sort/hash** của **mỗi** query (và mỗi worker song song) — đặt 256MB cho toàn server với 100 connection là rủi ro OOM. Tăng theo session/role cho báo cáo nặng. Với `LIMIT`, PostgreSQL chỉ cần giữ N dòng tốt nhất (*top-N heapsort*).

---

## Level 8 — Transaction

### 8.1

Khối `DO` chạy PL/pgSQL ẩn danh — có biến để giữ `order_id` giữa các bước, và chạy được trong DBeaver:

```sql
BEGIN;

DO $$
DECLARE
  v_order_id bigint;
  v_subtotal numeric(12,2);
  v_updated  int;
  -- 2 sản phẩm còn hàng; thử thay bằng sản phẩm hết hàng để thấy rollback:
  --   ARRAY(SELECT id FROM products WHERE status = 'OUT_OF_STOCK' LIMIT 2)
  v_products bigint[] := ARRAY(SELECT product_id FROM inventory
                               WHERE quantity - reserved_quantity >= 5
                               ORDER BY product_id LIMIT 2);
BEGIN
  -- 1. order (tổng tiền tạm = 0, cập nhật sau khi có dòng hàng)
  INSERT INTO orders (user_id, order_number, status, subtotal, discount, shipping_fee, total_amount, shipping_address)
  VALUES (42, 'LAB-' || to_char(clock_timestamp(), 'YYMMDDHH24MISSMS'), 'PENDING', 0, 0, 0, 0,   -- varchar(20)!
          (SELECT to_jsonb(a) - 'id' - 'user_id' - 'label' - 'is_default' - 'created_at'
           FROM addresses a WHERE a.user_id = 42 AND a.is_default))
  RETURNING id INTO v_order_id;

  -- 2. order_items: giá chốt tại thời điểm mua
  INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount, total_price)
  SELECT v_order_id, p.id, 1, p.price, 0, p.price
  FROM products p
  WHERE p.id = ANY (v_products);

  -- 3. tổng tiền
  SELECT sum(total_price) INTO v_subtotal FROM order_items WHERE order_id = v_order_id;
  UPDATE orders SET subtotal = v_subtotal, total_amount = v_subtotal WHERE id = v_order_id;

  -- 4. payment
  INSERT INTO payments (order_id, payment_method, amount, status)
  VALUES (v_order_id, 'CREDIT_CARD', v_subtotal, 'PENDING');

  -- 5. trừ kho ở kho còn nhiều hàng nhất của mỗi sản phẩm; điều kiện WHERE chống bán âm kho
  UPDATE inventory i
  SET quantity = quantity - 1
  WHERE i.id IN (SELECT DISTINCT ON (product_id) id
                 FROM inventory
                 WHERE product_id = ANY (v_products)
                 ORDER BY product_id, quantity - reserved_quantity DESC)
    AND i.quantity - i.reserved_quantity >= 1;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated < cardinality(v_products) THEN
    RAISE EXCEPTION 'out of stock (updated % of % inventory rows)', v_updated, cardinality(v_products);   -- => huỷ TOÀN BỘ transaction
  END IF;

  RAISE NOTICE 'created order % (subtotal %)', v_order_id, v_subtotal;
END $$;

SELECT id, order_number, status, subtotal, total_amount FROM orders WHERE order_number LIKE 'LAB-%';

ROLLBACK;   -- COMMIT để giữ lại; ROLLBACK để dữ liệu lab sạch
```

Nếu một sản phẩm hết hàng, `RAISE EXCEPTION` làm transaction lỗi → mọi INSERT/UPDATE trước đó cũng bị huỷ: đó chính là **Atomicity**.

Cố tình vi phạm constraint:

```sql
BEGIN;
INSERT INTO replication_test (token) VALUES ('tx-demo-1');
UPDATE inventory SET reserved_quantity = quantity + 1 WHERE id = 1;
-- ERROR: new row for relation "inventory" violates check constraint "ck_inventory_reserved"
SELECT 1;
-- ERROR: current transaction is aborted, commands ignored until end of transaction block
ROLLBACK;
SELECT count(*) FROM replication_test WHERE token = 'tx-demo-1';   -- 0: INSERT cũng bị huỷ
```

Sau một lỗi, transaction ở trạng thái *aborted*: mọi lệnh bị từ chối tới khi `ROLLBACK` (hoặc `ROLLBACK TO SAVEPOINT`).

### 8.2

```sql
BEGIN;
INSERT INTO replication_test (token) VALUES ('sp-line-1');

SAVEPOINT line2;
INSERT INTO replication_test (token) VALUES ('sp-line-1');     -- trùng UNIQUE -> lỗi
ROLLBACK TO SAVEPOINT line2;                                   -- chỉ huỷ phần sau savepoint

INSERT INTO replication_test (token) VALUES ('sp-line-3');
SELECT token FROM replication_test WHERE token LIKE 'sp-line-%';  -- sp-line-1, sp-line-3
ROLLBACK;                                                          -- (COMMIT nếu muốn giữ)
```

Savepoint = subtransaction (có XID con). Dùng quá nhiều (hàng nghìn/transaction) gây chi phí `SubtransSLRU`; ORM bật "savepoint mỗi câu lệnh" là nguồn chậm phổ biến.

### 8.3 — 8.6 👥

Làm theo kịch bản 2 session chi tiết trong [transaction-lab.md](transaction-lab.md):

| Bài | Mục trong transaction-lab |
|---|---|
| 8.3 | [Non-repeatable read](transaction-lab.md#3-non-repeatable-read) |
| 8.4 | [Repeatable Read & serialization failure](transaction-lab.md#6-isolation-level-read-committed-vs-repeatable-read-vs-serializable) |
| 8.5 | [Write skew & SERIALIZABLE](transaction-lab.md#62-write-skew-repeatable-read-cho-lọt-serializable-chặn) |
| 8.6 | [Lost update](transaction-lab.md#1-lost-update) |

Cách sửa lost update ở mức SQL (8.6):

```sql
-- (a) nguyên tử: đọc-tính-ghi trong MỘT câu lệnh, điều kiện chống âm kho
UPDATE inventory SET quantity = quantity - 2
WHERE id = 1 AND quantity - reserved_quantity >= 2
RETURNING quantity;

-- (b) pessimistic: khoá dòng trước khi đọc
BEGIN;
SELECT quantity FROM inventory WHERE id = 1 FOR UPDATE;
UPDATE inventory SET quantity = 17 WHERE id = 1;          -- giá trị app tính từ lần đọc trên
ROLLBACK;

-- (c) optimistic: chỉ ghi nếu không ai sửa từ lúc mình đọc
SELECT quantity, updated_at FROM inventory WHERE id = 1;  -- giả sử đọc được '2025-01-01 10:00:00+00'
UPDATE inventory SET quantity = 17
WHERE id = 1 AND updated_at = '2025-01-01 10:00:00+00';   -- 0 dòng = có người sửa trước -> đọc lại và thử lại
```

---

## Level 9 — Locking

### 9.1 👥

Kịch bản: [transaction-lab.md §5](transaction-lab.md#5-row-lock-select--for-update). Truy vấn từ session thứ 3:

```sql
SELECT pid, pg_blocking_pids(pid) AS blocked_by, wait_event_type, wait_event, state, left(query, 60)
FROM pg_stat_activity
WHERE datname = 'ecommerce' AND pid <> pg_backend_pid();

SELECT l.pid, l.locktype, l.relation::regclass, l.transactionid, l.mode, l.granted
FROM pg_locks l
WHERE l.pid IN (SELECT pid FROM pg_stat_activity WHERE datname = 'ecommerce' AND pid <> pg_backend_pid())
ORDER BY l.granted, l.pid;
```

Session B chờ `ShareLock` trên **`transactionid`** của A (không phải trên dòng!): row lock nằm trong header tuple (`xmax` = XID của A), nên người chờ xếp hàng chờ transaction A kết thúc. Bản đầy đủ: [sql/monitoring/locks.sql](../sql/monitoring/locks.sql).

### 9.2

```sql
-- mỗi worker chạy (có thể song song ở nhiều session):
BEGIN;
SELECT id, order_id, amount
FROM payments
WHERE status = 'PENDING'
ORDER BY created_at
LIMIT 10
FOR UPDATE SKIP LOCKED;
-- ... xử lý, rồi:
-- UPDATE payments SET status = 'SUCCEEDED', paid_at = now(), transaction_id = gen_random_uuid() WHERE id IN (...);
ROLLBACK;   -- COMMIT trong thực tế
```

Worker thứ hai nhận 10 dòng **khác** thay vì chờ worker thứ nhất. Thêm partial index ở bài 6.4 để `WHERE status='PENDING' ORDER BY created_at` không phải quét bảng.

### 9.3 👥

```sql
-- Session A
BEGIN; SELECT * FROM inventory WHERE id = 1 FOR UPDATE;

-- Session B
SELECT * FROM inventory WHERE id = 1 FOR UPDATE NOWAIT;
-- ERROR:  could not obtain lock on row in relation "inventory"
SET lock_timeout = '2s';
UPDATE inventory SET quantity = quantity WHERE id = 1;
-- (2 giây sau) ERROR:  canceling statement due to lock timeout
RESET lock_timeout;

-- Session A
ROLLBACK;
```

### 9.4 👥

Kịch bản: [transaction-lab.md §7](transaction-lab.md#7-deadlock). Sửa: mọi code path khoá dòng theo cùng thứ tự, ví dụ luôn `ORDER BY id`:

```sql
BEGIN;
SELECT id FROM inventory WHERE id IN (1, 2) ORDER BY id FOR UPDATE;
UPDATE inventory SET quantity = quantity + 1 WHERE id = 2;
UPDATE inventory SET quantity = quantity - 1 WHERE id = 1;
ROLLBACK;
```

### 9.5 👥

```sql
-- Session A: một transaction "vô hại" chưa kết thúc
BEGIN; SELECT count(*) FROM products;          -- giữ AccessShareLock tới khi COMMIT

-- Session B: DDL cần AccessExclusiveLock -> chờ A
ALTER TABLE products ADD COLUMN lab_note text;

-- Session C: SELECT bình thường cũng bị treo! (xếp hàng SAU B)
SELECT count(*) FROM products WHERE id < 10;
```

Hàng đợi lock là FIFO: yêu cầu `AccessShareLock` của C xung đột với `AccessExclusiveLock` **đang chờ** của B → C chờ sau B. Một transaction bị bỏ quên + một lệnh DDL = cả bảng đứng hình. Cách an toàn:

```sql
SET lock_timeout = '3s';                               -- thất bại nhanh thay vì chặn mọi người
ALTER TABLE products ADD COLUMN lab_note text;         -- thử lại nhiều lần nếu lỗi
CREATE INDEX CONCURRENTLY idx_products_brand ON products (brand);   -- không chặn ghi (không chạy trong BEGIN)
```

Dọn dẹp: `ALTER TABLE products DROP COLUMN IF EXISTS lab_note; DROP INDEX IF EXISTS idx_products_brand;`

### 9.6

```sql
-- mỗi instance job chạy:
SELECT pg_try_advisory_lock(hashtext('daily-sales-report')) AS got_lock;
-- true  -> được chạy job
-- false -> đã có instance khác đang chạy, thoát

-- ... chạy job ...

SELECT pg_advisory_unlock(hashtext('daily-sales-report'));
```

Advisory lock là lock "theo quy ước" do ứng dụng đặt tên bằng số (bigint); PostgreSQL chỉ đảm bảo loại trừ lẫn nhau. Lock mức session tồn tại tới khi unlock hoặc ngắt kết nối; bản `pg_try_advisory_xact_lock` tự nhả khi transaction kết thúc.

---

## Level 10 — PostgreSQL Internals

### 10.1

```sql
SELECT xmin, xmax, ctid, id, price FROM products WHERE id = 1;
--  xmin |xmax| ctid  | id | price
-- ------+----+-------+----+-------
--   882 |  0 | (0,1) |  1 |  3.23

SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'products';

BEGIN;
UPDATE products SET price = price + 1 WHERE id = 1;
SELECT xmin, xmax, ctid, id, price, pg_current_xact_id() FROM products WHERE id = 1;
-- xmin = XID hiện tại, ctid đổi: phiên bản MỚI của dòng nằm ở vị trí khác
COMMIT;

SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'products';
-- (số liệu thống kê được gửi sau khi transaction kết thúc, có thể trễ một chút)
UPDATE products SET price = price - 1 WHERE id = 1;     -- trả lại giá cũ
```

UPDATE trong PostgreSQL = **đánh dấu phiên bản cũ đã chết** (`xmax` = XID của mình) + **chèn phiên bản mới**. Nếu (1) không cột nào có index bị đổi và (2) page còn chỗ, bản mới nằm cùng page và **không cần** thêm entry index: *HOT update* (Heap-Only Tuple). `price` có index `idx_products_price` → cập nhật price **không** HOT. Thử `UPDATE products SET description = description WHERE id = 1` để thấy HOT. Chi tiết: [mvcc-lab.md](mvcc-lab.md).

### 10.2

```sql
INSERT INTO replication_test (token) VALUES ('pi-1'), ('pi-2'), ('pi-3');
UPDATE replication_test SET note = 'updated' WHERE token = 'pi-2';
DELETE FROM replication_test WHERE token = 'pi-3';

SELECT lp, lp_flags, t_xmin, t_xmax, t_ctid, t_infomask2, t_infomask
FROM heap_page_items(get_raw_page('replication_test', 0))
ORDER BY lp;
```

- `lp_flags`: 1 = NORMAL, 2 = REDIRECT (HOT chain sau prune), 3 = DEAD, 0 = UNUSED.
- Tuple `pi-2` cũ: `t_xmax` = XID của UPDATE, `t_ctid` trỏ tới vị trí bản mới.
- Tuple `pi-3`: `t_xmax` = XID của DELETE, `t_ctid` trỏ về chính nó.
- Bản ghi vẫn nằm vật lý trên page tới khi VACUUM (hoặc page pruning) dọn.

### 10.3

```sql
SELECT pg_size_pretty(pg_table_size('orders')) AS before_size;

UPDATE orders SET note = note WHERE id <= 50000;    -- không đổi giá trị, nhưng vẫn tạo 50k phiên bản mới + 50k dead
SELECT n_live_tup, n_dead_tup FROM pg_stat_user_tables WHERE relname = 'orders';

SELECT tuple_count, dead_tuple_count, round(dead_tuple_percent::numeric, 2) AS dead_pct, free_percent
FROM pgstattuple('orders');

VACUUM (VERBOSE) orders;       -- đánh dấu không gian dead tái sử dụng được, KHÔNG trả cho OS
SELECT pg_size_pretty(pg_table_size('orders')) AS after_vacuum;

VACUUM FULL orders;            -- viết lại toàn bộ bảng: thu hồi dung lượng, nhưng khoá AccessExclusive!
SELECT pg_size_pretty(pg_table_size('orders')) AS after_vacuum_full;
```

`VACUUM FULL` chặn cả đọc lẫn ghi suốt thời gian chạy và tạo ra lượng WAL bằng cả bảng (replica phải nhận hết). Thực tế dùng `pg_repack` hoặc chỉ `VACUUM` thường + để autovacuum làm việc.

### 10.4

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE created_at >= now() - interval '60 days';
-- Index Only Scan using idx_orders_created_at ... Heap Fetches: 0

UPDATE orders SET note = note WHERE created_at >= now() - interval '60 days';

EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE created_at >= now() - interval '60 days';
-- Heap Fetches: hàng chục nghìn -> Index Only Scan phải ghé heap để kiểm tra visibility

VACUUM orders;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE created_at >= now() - interval '60 days';
-- Heap Fetches: 0 trở lại
```

Index không chứa thông tin visibility (xmin/xmax). Index Only Scan chỉ bỏ qua heap được khi page được đánh dấu *all-visible* trong **visibility map** — việc mà VACUUM làm.

### 10.5

```sql
CHECKPOINT;
SELECT pg_current_wal_lsn() AS lsn0 \gset
UPDATE products SET cost = cost WHERE id BETWEEN 1 AND 10000;
SELECT pg_current_wal_lsn() AS lsn1 \gset
UPDATE products SET cost = cost WHERE id BETWEEN 1 AND 10000;
SELECT pg_current_wal_lsn() AS lsn2 \gset

SELECT pg_size_pretty(pg_wal_lsn_diff(:'lsn1', :'lsn0')) AS first_update_after_checkpoint,
       pg_size_pretty(pg_wal_lsn_diff(:'lsn2', :'lsn1')) AS second_update;

SELECT "resource_manager/record_type" AS resource_manager, count, round(count_percentage::numeric, 1) AS pct,
       pg_size_pretty(combined_size) AS size, round(combined_size_percentage::numeric, 1) AS size_pct
FROM pg_get_wal_stats(:'lsn0', :'lsn1')
WHERE count > 0
ORDER BY combined_size DESC;
```

Lần UPDATE đầu sau checkpoint phải ghi **full page image** cho mỗi page chạm tới → WAL lớn hơn nhiều lần so với lần thứ hai. Đây là lý do WAL tăng vọt ngay sau mỗi checkpoint, và vì sao `checkpoint_timeout`/`max_wal_size` lớn hơn giúp giảm WAL. (Trong DBeaver không có `\gset`: chạy `SELECT pg_current_wal_lsn()`, chép giá trị vào truy vấn sau.)

### 10.6

```sql
SELECT pg_relation_filepath('orders');          -- base/16384/16758  (tương đối với PGDATA)
SELECT oid, datname FROM pg_database;

SELECT c.relname, t.relname AS toast_table, pg_size_pretty(pg_relation_size(t.oid)) AS toast_size
FROM pg_class c
JOIN pg_class t ON t.oid = c.reltoastrelid
WHERE c.relname IN ('reviews', 'orders', 'products');

SELECT datname, datfrozenxid, age(datfrozenxid) AS xid_age,
       round(100.0 * age(datfrozenxid) / 2000000000, 4) AS pct_to_wraparound
FROM pg_database
ORDER BY xid_age DESC;
```

```bash
docker compose exec postgres-primary ls -la /var/lib/postgresql/data/base/16384/ | head
```

- Mỗi bảng/index là một (hoặc nhiều, mỗi file 1GB) file trong `base/<db oid>/`; kèm `_fsm` (free space map) và `_vm` (visibility map).
- Giá trị lớn hơn ~2KB được nén và/hoặc tách ra bảng **TOAST** riêng.
- XID là số 32-bit → sau ~2 tỷ transaction sẽ quay vòng. VACUUM "đóng băng" (freeze) tuple cũ để chúng luôn được coi là quá khứ. Nếu `age(datfrozenxid)` tiến gần 2 tỷ, PostgreSQL sẽ từ chối ghi để bảo vệ dữ liệu — lý do không bao giờ được tắt autovacuum.
