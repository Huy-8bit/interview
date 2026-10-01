# Index Lab — B-tree, composite, partial, expression, covering, GIN, trigram, BRIN

Chạy trên **primary** (`localhost:5432`). Mọi số liệu trong bài đo trên dataset mặc định (100k users, 500k orders, 1.5M order_items, `SEED=42`) sau khi generator chạy `VACUUM ANALYZE`. Máy bạn sẽ ra số khác — hãy so **thứ tự độ lớn** và **loại node** trong plan.

Quy tắc của lab:

- Mỗi bài: chạy plan **trước**, tạo index, chạy plan **sau**, so `Execution Time` + `Buffers`, rồi **`DROP INDEX`** để trả lab về trạng thái ban đầu (các bài khác và [sql-exercises.md](sql-exercises.md) giả định index chưa có).
- Đo bằng `EXPLAIN (ANALYZE, BUFFERS)`. Chạy 2 lần, lấy lần thứ 2 (lần đầu có thể phải đọc đĩa: `read=` thay vì `hit=`).
- `Buffers: shared hit=N` = N trang 8 KB đọc từ shared_buffers; `read=N` = đọc từ OS/đĩa. **Buffers là thước đo ổn định hơn thời gian.**

Mẹo DBeaver: bôi đen câu `EXPLAIN ...` rồi *Ctrl+Enter* để xem plan dạng text; hoặc dùng *Explain Execution Plan* (Ctrl+Shift+E) để xem dạng cây.

---

## 0. Index đang có

```sql
SELECT t.relname AS table_name, i.relname AS index_name, am.amname AS type,
       ix.indisunique AS is_unique, ix.indpred IS NOT NULL AS is_partial, ix.indexprs IS NOT NULL AS is_expression,
       pg_get_indexdef(ix.indexrelid) AS definition,
       pg_size_pretty(pg_relation_size(ix.indexrelid)) AS size
FROM pg_index ix
JOIN pg_class i  ON i.oid = ix.indexrelid
JOIN pg_class t  ON t.oid = ix.indrelid
JOIN pg_am    am ON am.oid = i.relam
WHERE t.relnamespace = 'public'::regnamespace
ORDER BY t.relname, i.relname;
```

Mỗi loại đã có sẵn ít nhất một mẫu (xem [04-indexes.sql](../postgres/primary/init/04-indexes.sql)):

| Loại | Index mẫu |
| --- | --- |
| B-tree một cột | `idx_orders_user_id`, `idx_products_price` |
| Composite | `idx_orders_status_created_at (status, created_at)` |
| Unique | `uq_products_sku`, `uq_orders_order_number` |
| Unique + expression | `ux_users_email_lower ON users (lower(email))` |
| Partial | `idx_orders_open_created_at ... WHERE status IN ('PENDING','CONFIRMED','PROCESSING')` |
| Partial unique | `ux_addresses_one_default_per_user ON addresses (user_id) WHERE is_default` |
| GIN (jsonb) | `idx_products_attributes_gin USING gin (attributes jsonb_path_ops)` |

Và **cố ý thiếu** (đây là bài tập của bạn): `users.phone`, `users.status`, `products.name` (tìm kiếm chuỗi), `products.tags`, `orders(user_id, status, created_at)`, `payments.status`, `reviews.order_id` (FK!), `inventory.warehouse_id` (FK!)…

---

## 1. B-tree một cột: tìm user theo số điện thoại

```sql
-- lấy một số điện thoại có thật
SELECT phone FROM users WHERE id = 777;                       -- +1-915-884-7227

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, username FROM users WHERE phone = '+1-915-884-7227';
```

Trước:

```text
Seq Scan on users (actual rows=1 loops=1)
  Filter: ((phone)::text = '+1-915-884-7227'::text)
  Rows Removed by Filter: 99999
  Buffers: shared hit=4 read=4983
Execution Time: 63.646 ms
```

Đọc **toàn bộ 4,987 trang** (39 MB) để lấy 1 dòng.

```sql
CREATE INDEX idx_users_phone ON users (phone);
-- chạy lại EXPLAIN ở trên
```

Sau:

```text
Index Scan using idx_users_phone on users (actual rows=1 loops=1)
  Index Cond: ((phone)::text = '+1-915-884-7227'::text)
  Buffers: shared hit=4 read=3
Execution Time: 0.053 ms
```

7 trang thay vì 4,987 (~1,000 lần nhanh hơn). Giá phải trả:

```sql
SELECT pg_size_pretty(pg_relation_size('idx_users_phone'));   -- 2744 kB
```

…và **mỗi** `INSERT`/`UPDATE phone`/`DELETE` trên `users` giờ phải cập nhật thêm một cây B-tree. Index chỉ đáng giá khi truy vấn đó thực sự chạy thường xuyên.

**Tự làm**: `WHERE phone LIKE '+1-915%'` có dùng index không? (Gợi ý: database được tạo với collation `en_US.utf8`; B-tree thường chỉ phục vụ `LIKE 'prefix%'` khi collation là `C` hoặc index tạo với `varchar_pattern_ops`. Thử `CREATE INDEX ... (phone varchar_pattern_ops)`.)

```sql
DROP INDEX idx_users_phone;
```

---

## 2. Khi nào planner **không** dùng index: selectivity

```sql
EXPLAIN SELECT * FROM orders WHERE status = 'COMPLETED';    -- 60% số dòng
EXPLAIN SELECT * FROM orders WHERE status = 'CONFIRMED';    -- 5% số dòng
```

```text
Seq Scan on orders
  Filter: (status = 'COMPLETED'::order_status)

Index Scan using idx_orders_open_created_at on orders
  Filter: (status = 'CONFIRMED'::order_status)
```

- `COMPLETED` chiếm ~60%: đọc tuần tự cả bảng **rẻ hơn** nhảy qua index rồi đọc ngẫu nhiên gần như mọi trang heap.
- `CONFIRMED` chỉ 5% và **nằm trong điều kiện của partial index** `idx_orders_open_created_at` → planner dùng partial index (nhỏ, 1.9 MB) rồi lọc lại `status`.

Planner biết tỷ lệ này từ thống kê:

```sql
SELECT most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'orders' AND attname = 'status';
```

**Tự làm**: chạy `EXPLAIN` cho cả 6 giá trị status. Ngưỡng chuyển từ index sang Seq Scan ở đâu? Thử `SET random_page_cost = 4;` (giá trị mặc định cho HDD — lab đặt 1.1 cho SSD) và quan sát ngưỡng dịch chuyển. `RESET random_page_cost;` khi xong.

---

## 3. Composite index và quy tắc leftmost prefix

Có sẵn `idx_orders_status_created_at (status, created_at)`. So sánh 3 truy vấn:

```sql
-- (a) cả 2 cột: dùng index trọn vẹn
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE status = 'SHIPPED' AND created_at >= now() - interval '7 days';

-- (b) chỉ cột đầu: vẫn dùng được (prefix)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE status = 'SHIPPED';

-- (c) chỉ cột thứ hai: KHÔNG dùng được composite này như một cây tìm kiếm
--     (planner chọn idx_orders_created_at riêng)
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE created_at >= now() - interval '7 days';
```

Hình dung composite index như danh bạ sắp theo (họ, tên): tìm "họ Nguyễn" hay "Nguyễn Văn A" thì nhanh; tìm "mọi người tên A" thì phải lật cả cuốn.

### 3.1 Bài tập: tối ưu truy vấn "đơn hàng của tôi"

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE user_id = 55368 AND status = 'COMPLETED'
ORDER BY created_at DESC;
```

Hiện tại (user 55368 là user có nhiều đơn nhất: 36 đơn):

```text
Sort (actual rows=23 loops=1)
  Sort Key: created_at DESC
  Sort Method: quicksort  Memory: 31kB
  ->  Index Scan using idx_orders_user_id on orders (actual rows=23 loops=1)
        Index Cond: (user_id = 55368)
        Filter: (status = 'COMPLETED'::order_status)
        Rows Removed by Filter: 13
```

Ba dấu hiệu cần tối ưu: `Filter` + `Rows Removed by Filter` (đọc dòng rồi vứt đi) và node `Sort` riêng.

Tạo index khớp **cả** điều kiện bằng (`user_id`, `status`) lẫn thứ tự sắp xếp (`created_at DESC`):

```sql
CREATE INDEX idx_orders_user_status_created ON orders (user_id, status, created_at DESC);
```

Kỳ vọng: `Index Scan using idx_orders_user_status_created`, không còn `Filter`, không còn `Sort`. Với `LIMIT 10` truy vấn dừng sau 10 entry index.

Câu hỏi:

1. Đổi thứ tự thành `(user_id, created_at DESC, status)` thì sao? Khi nào thứ tự này tốt hơn?
2. Sau khi có index mới, `idx_orders_user_id` có còn cần không? (Xem mục 9.)

```sql
DROP INDEX idx_orders_user_status_created;
```

---

## 4. Expression index: `lower(email)`

```sql
SELECT email FROM users WHERE id = 4242;    -- ncunningham4242@gmail.com

EXPLAIN SELECT * FROM users WHERE email = 'ncunningham4242@gmail.com';
EXPLAIN SELECT * FROM users WHERE lower(email) = lower('NCunningham4242@gmail.com');
```

```text
Seq Scan on users
  Filter: ((email)::text = 'ncunningham4242@gmail.com'::text)

Index Scan using ux_users_email_lower on users
  Index Cond: (lower((email)::text) = 'ncunningham4242@gmail.com'::text)
```

Index biểu thức chỉ khớp khi câu truy vấn viết **đúng biểu thức** đó. `ux_users_email_lower` còn là UNIQUE: `Foo@x.com` và `foo@x.com` không thể cùng tồn tại — điều mà constraint `UNIQUE (email)` thường không làm được.

```sql
-- ~5% email được sinh có chữ hoa: query "=" thường sẽ bỏ sót họ
SELECT count(*) FROM users WHERE email <> lower(email);
```

**Tự làm**: các hàm khác cũng tạo được expression index, nhưng phải là `IMMUTABLE`. Vì sao `CREATE INDEX ON orders ((created_at::date))` báo lỗi? (`timestamptz → date` phụ thuộc `TimeZone` → không immutable.) Viết lại bằng `((created_at AT TIME ZONE 'UTC')::date)`.

---

## 5. Partial index

Có sẵn:

```sql
CREATE INDEX idx_orders_open_created_at ON orders (created_at)
  WHERE status IN ('PENDING', 'CONFIRMED', 'PROCESSING');
```

So sánh kích thước:

```sql
SELECT pg_size_pretty(pg_relation_size('idx_orders_created_at'))      AS full_index,     -- 11 MB
       pg_size_pretty(pg_relation_size('idx_orders_open_created_at')) AS partial_index;  -- 1904 kB
```

Partial index được dùng khi điều kiện `WHERE` của query **suy ra được** điều kiện của index:

```sql
-- dùng partial index: status = 'PENDING' ⊂ IN ('PENDING','CONFIRMED','PROCESSING')
EXPLAIN (ANALYZE)
SELECT id, created_at FROM orders
WHERE status = 'PENDING' AND created_at < now() - interval '3 days'
ORDER BY created_at LIMIT 50;
```

```text
Limit (actual rows=50 loops=1)
  ->  Index Scan using idx_orders_open_created_at on orders (actual rows=50 loops=1)
        Index Cond: (created_at < (now() - '3 days'::interval))
        Filter: (status = 'PENDING'::order_status)
        Rows Removed by Filter: 33225
```

Vẫn còn `Rows Removed by Filter: 33225` vì index trộn 3 status. **Bài tập**: tạo partial index chỉ cho `PENDING` và so sánh. Tương tự cho bảng `payments`:

```sql
-- "payment PENDING quá 1 ngày" - job đối soát chạy mỗi phút
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_id, created_at FROM payments
WHERE status = 'PENDING' AND created_at < now() - interval '1 day';

CREATE INDEX idx_payments_pending_created ON payments (created_at) WHERE status = 'PENDING';
CREATE INDEX idx_payments_status_created  ON payments (status, created_at);     -- để so sánh
SELECT pg_size_pretty(pg_relation_size('idx_payments_pending_created')) AS partial,
       pg_size_pretty(pg_relation_size('idx_payments_status_created'))  AS full;
DROP INDEX idx_payments_pending_created, idx_payments_status_created;
```

Partial **unique** index — "mỗi user tối đa 1 địa chỉ mặc định":

```sql
BEGIN;
INSERT INTO addresses (user_id, recipient_name, line1, city, is_default)
VALUES (1, 'Test', '1 Main St', 'Austin', true);
-- ERROR:  duplicate key value violates unique constraint "ux_addresses_one_default_per_user"
ROLLBACK;
```

---

## 6. Covering index (`INCLUDE`) và Index Only Scan

Sản phẩm bán chạy nhất (`product_id = 28148`, 6,149 dòng order_items):

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT sum(quantity) FROM order_items WHERE product_id = 28148;
```

Trước:

```text
Aggregate (actual rows=1 loops=1)
  Buffers: shared hit=5008
  ->  Bitmap Heap Scan on order_items (actual rows=6149 loops=1)
        Recheck Cond: (product_id = 28148)
        Heap Blocks: exact=5001
        ->  Bitmap Index Scan on idx_order_items_product_id (actual rows=6149 loops=1)
              Buffers: shared hit=7
Execution Time: 5.606 ms
```

Index tìm 6,149 dòng chỉ trong 7 trang, nhưng sau đó phải đọc **5,001 trang heap** để lấy cột `quantity` — vì các dòng của một sản phẩm nằm rải rác khắp bảng.

```sql
CREATE INDEX idx_order_items_product_qty ON order_items (product_id) INCLUDE (quantity);
VACUUM order_items;    -- cập nhật visibility map (xem bên dưới)
```

Sau:

```text
Aggregate (actual rows=1 loops=1)
  Buffers: shared hit=4 read=26
  ->  Index Only Scan using idx_order_items_product_qty on order_items (actual rows=6149 loops=1)
        Index Cond: (product_id = 28148)
        Heap Fetches: 0
Execution Time: 0.462 ms
```

30 trang thay vì 5,008. Hai điều cần hiểu:

1. **`Heap Fetches`**: Index Only Scan vẫn phải kiểm tra tính khả kiến (MVCC). Nếu trang heap được đánh dấu *all-visible* trong visibility map thì bỏ qua heap; nếu không thì phải đọc heap (`Heap Fetches > 0`). Chỉ `VACUUM` mới set bit này. Thử `UPDATE order_items SET quantity = quantity WHERE product_id = 28148;` rồi chạy lại — `Heap Fetches` tăng vọt cho tới lần VACUUM sau. (Chi tiết: [mvcc-lab.md §6](mvcc-lab.md#6-visibility-map-và-index-only-scan).)
2. **Kích thước**:

```sql
SELECT pg_size_pretty(pg_relation_size('idx_order_items_product_qty')) AS covering,  -- 45 MB
       pg_size_pretty(pg_relation_size('idx_order_items_product_id'))  AS plain;     -- 16 MB
```

Covering index to gần **3 lần** chứ không chỉ "thêm một cột int". Lý do: từ PG13, B-tree **deduplication** gộp các entry có cùng key (`product_id` lặp lại trung bình 17 lần) thành một entry + danh sách TID. Có cột `INCLUDE` thì mỗi entry khác nhau → mất deduplication. Đánh đổi thật sự: 29 MB và chi phí ghi, đổi lấy truy vấn nhanh hơn ~10 lần.

```sql
DROP INDEX idx_order_items_product_qty;
```

---

## 7. GIN: JSONB, mảng và tìm kiếm chuỗi

### 7.1 JSONB containment

`idx_products_attributes_gin` dùng operator class `jsonb_path_ops`: nhỏ và nhanh, nhưng **chỉ** hỗ trợ `@>` (và jsonpath `@?`, `@@`).

```sql
-- dùng GIN
EXPLAIN (ANALYZE) SELECT count(*) FROM products WHERE attributes @> '{"color": "Pink"}';
-- KHÔNG dùng GIN: ->> trả về text, GIN không biết gì về biểu thức này
EXPLAIN (ANALYZE) SELECT count(*) FROM products WHERE attributes ->> 'color' = 'Pink';
```

```text
Bitmap Heap Scan on products (actual rows=1291 loops=1)
  Recheck Cond: (attributes @> '{"color": "Pink"}'::jsonb)
  ->  Bitmap Index Scan on idx_products_attributes_gin (actual rows=1291 loops=1)
Execution Time: 8.954 ms

Seq Scan on products
  Filter: ((attributes ->> 'color'::text) = 'Pink'::text)
```

Truy vấn lồng sâu cũng dùng được `@>`:

```sql
EXPLAIN SELECT id, name FROM products WHERE attributes @> '{"specs": {"ram_gb": 64}}';
```

**Tự làm**:

1. `WHERE attributes ? 'flavor'` (có key `flavor`) có dùng `jsonb_path_ops` không? Tạo `CREATE INDEX ... USING gin (attributes)` (opclass mặc định `jsonb_ops`) và so sánh kích thước hai index.
2. Nếu luôn lọc theo **một** key cố định, một B-tree expression index `((attributes ->> 'color'))` nhỏ hơn GIN rất nhiều. Thử.

### 7.2 Mảng `text[]`

```sql
EXPLAIN (ANALYZE) SELECT count(*) FROM products WHERE tags @> ARRAY['limited-edition'];
CREATE INDEX idx_products_tags_gin ON products USING gin (tags);
EXPLAIN (ANALYZE) SELECT count(*) FROM products WHERE tags @> ARRAY['limited-edition'];   -- 4,224 dòng
EXPLAIN (ANALYZE) SELECT count(*) FROM products WHERE tags @> ARRAY['sale'];              -- 22,298 dòng
DROP INDEX idx_products_tags_gin;
```

| Truy vấn | Không index | GIN |
| --- | --- | --- |
| `tags @> '{limited-edition}'` (4%) | Seq Scan, 16.4 ms | Bitmap Heap Scan, 2.0 ms |
| `tags @> '{sale}'` (22%) | Seq Scan | Bitmap Heap Scan, 4.3 ms |

Lưu ý `WHERE 'sale' = ANY(tags)` **không** dùng được GIN — phải viết dạng operator `@>`, `&&`.

### 7.3 `ILIKE '%...%'` với `pg_trgm`

B-tree không giúp được `LIKE` có `%` ở đầu. Extension `pg_trgm` (đã cài) tách chuỗi thành các bộ 3 ký tự (trigram) và đánh index GIN trên đó:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT id, name FROM products WHERE name ILIKE '%air fryer%';
CREATE INDEX idx_products_name_trgm ON products USING gin (name gin_trgm_ops);
EXPLAIN (ANALYZE, BUFFERS) SELECT id, name FROM products WHERE name ILIKE '%air fryer%';
```

| | Plan | Thời gian |
| --- | --- | --- |
| Trước | `Seq Scan`, `Rows Removed by Filter: 99403` | 57.7 ms |
| Sau | `Bitmap Index Scan on idx_products_name_trgm` | 1.1 ms |

Index nặng 9 MB. Thêm: tìm gần đúng (gõ sai chính tả):

```sql
SELECT name, similarity(name, 'Samsng Galxy Smartphone') AS sim
FROM products
WHERE name % 'Samsng Galxy Smartphone'        -- % = "đủ giống" (pg_trgm.similarity_threshold, mặc định 0.3)
ORDER BY sim DESC LIMIT 5;

DROP INDEX idx_products_name_trgm;
```

---

## 8. BRIN: index siêu nhỏ cho dữ liệu "theo thời gian"

`orders.id` và `orders.created_at` được sinh theo thứ tự thời gian, nên thứ tự vật lý trên đĩa tương quan hoàn hảo với `created_at`:

```sql
SELECT attname, correlation FROM pg_stats
WHERE tablename = 'orders' AND attname IN ('id', 'created_at', 'user_id', 'total_amount');
--  id 1, created_at 1, user_id 0.43, total_amount -0.001
```

BRIN chỉ lưu min/max cho mỗi khối 128 trang. Với correlation ≈ 1, như vậy là đủ để loại hầu hết các khối:

```sql
CREATE INDEX idx_orders_created_brin ON orders USING brin (created_at);

SELECT pg_size_pretty(pg_relation_size('idx_orders_created_brin')) AS brin,    -- 24 kB
       pg_size_pretty(pg_relation_size('idx_orders_created_at'))   AS btree;   -- 11 MB
```

Để so sánh công bằng, **tạm** bỏ các B-tree trên `created_at` trong một transaction (DDL trong PostgreSQL là transactional, `ROLLBACK` sẽ trả lại index — nhưng giữ lock bảng, chỉ làm trên lab):

```sql
BEGIN;
DROP INDEX idx_orders_created_at, idx_orders_status_created_at, idx_orders_open_created_at;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount) FROM orders
WHERE created_at >= '2025-03-01' AND created_at < '2025-03-08';
ROLLBACK;
```

```text
Bitmap Heap Scan on orders (actual rows=883 loops=1)
  Rows Removed by Index Recheck: 2317
  Heap Blocks: lossy=128
  Buffers: shared hit=5 read=128
  ->  Bitmap Index Scan on idx_orders_created_brin (actual rows=1280 loops=1)
        Buffers: shared hit=5
Execution Time: 0.636 ms
```

BRIN là *lossy*: trả về cả khối 128 trang, phải `Recheck` từng dòng (`Rows Removed by Index Recheck`). Với B-tree cùng truy vấn: `Buffers: 41`, 1.2 ms. BRIN nhỏ hơn **450 lần** mà tốc độ tương đương cho truy vấn khoảng thời gian.

**Tự làm**: tạo BRIN trên `orders (user_id)` (correlation 0.43) và trên `orders (total_amount)` (correlation ≈ 0). Truy vấn `WHERE total_amount BETWEEN 100 AND 101` — BRIN còn loại được khối nào không?

```sql
DROP INDEX idx_orders_created_brin;
```

---

## 9. Index thừa và index không dùng

Một B-tree trên `(a, b)` đã phục vụ được mọi tìm kiếm theo `(a)`. Truy vấn tìm index là **prefix** của index khác trên cùng bảng:

```sql
SELECT a.indexrelid::regclass AS redundant_index,
       b.indexrelid::regclass AS covered_by,
       pg_size_pretty(pg_relation_size(a.indexrelid)) AS wasted
FROM pg_index a
JOIN pg_index b ON b.indrelid = a.indrelid AND b.indexrelid <> a.indexrelid
JOIN pg_class ca ON ca.oid = a.indexrelid
JOIN pg_class cb ON cb.oid = b.indexrelid
WHERE ca.relam = cb.relam                                   -- cùng loại (btree với btree)
  AND a.indpred IS NULL AND b.indpred IS NULL               -- không partial
  AND a.indexprs IS NULL AND b.indexprs IS NULL             -- không expression
  AND NOT a.indisunique                                     -- index unique còn là constraint, không xoá
  AND (b.indkey::text = a.indkey::text OR b.indkey::text LIKE a.indkey::text || ' %')
  AND ca.relnamespace = 'public'::regnamespace;
```

```text
     redundant_index      |          covered_by          | wasted
--------------------------+------------------------------+--------
 idx_categories_parent_id | uq_categories_parent_name    | 16 kB
 idx_order_items_order_id | uq_order_items_order_product | 22 MB
```

`idx_order_items_order_id` được **cố ý** tạo thừa. Trước khi xoá, chứng minh truy vấn vẫn dùng được index còn lại:

```sql
BEGIN;
DROP INDEX idx_order_items_order_id;
EXPLAIN SELECT * FROM order_items WHERE order_id = 250000;
-- Index Scan using uq_order_items_order_product on order_items
ROLLBACK;     -- hoặc COMMIT nếu bạn quyết định xoá thật
```

Không phải index thừa nào cũng nên xoá: index nhỏ hơn (1 cột) quét nhanh hơn một chút và có thể Index Only Scan rẻ hơn. Với 22 MB và chi phí ghi trên bảng 1.5M dòng, ở đây xoá là hợp lý.

Index **chưa từng được dùng** kể từ lần reset thống kê:

```sql
SELECT relname AS table_name, indexrelname AS index_name, idx_scan,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
ORDER BY idx_scan, pg_relation_size(indexrelid) DESC;
```

Cẩn thận: `idx_scan = 0` không có nghĩa là xoá được — index UNIQUE/PK đang bảo vệ tính toàn vẹn dữ liệu; và replica có thống kê riêng (truy vấn chạy trên replica không tăng `idx_scan` trên primary).

---

## 10. Foreign key không có index

PostgreSQL tự tạo index cho PRIMARY KEY / UNIQUE, nhưng **không** tự tạo cho cột FOREIGN KEY ở bảng con. Tìm chúng:

```sql
SELECT c.conrelid::regclass AS child_table, c.conname AS fk,
       string_agg(a.attname, ', ' ORDER BY k.ord) AS fk_columns,
       c.confrelid::regclass AS parent_table
FROM pg_constraint c
CROSS JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
WHERE c.contype = 'f'
  AND c.connamespace = 'public'::regnamespace
  AND NOT EXISTS (SELECT 1 FROM pg_index i
                  WHERE i.indrelid = c.conrelid AND i.indkey[0] = c.conkey[1])
GROUP BY c.conrelid, c.conname, c.confrelid
ORDER BY 1;
```

```text
 child_table |           fk           |  fk_columns  | parent_table
-------------+------------------------+--------------+--------------
 inventory   | fk_inventory_warehouse | warehouse_id | warehouses
 reviews     | fk_reviews_order       | order_id     | orders
```

Hệ quả: **mỗi** `DELETE FROM orders` (hoặc UPDATE `orders.id`) phải quét toàn bộ `reviews` để thực thi `ON DELETE SET NULL`:

```sql
BEGIN;
EXPLAIN (ANALYZE) DELETE FROM orders WHERE id = 250001;
ROLLBACK;
```

```text
Delete on orders (actual time=0.055..0.055 rows=0 loops=1)
  ->  Index Scan using pk_orders on orders (actual time=0.023..0.023 rows=1 loops=1)
Trigger for constraint fk_order_items_order: time=0.153 calls=1     <- có index
Trigger for constraint fk_payments_order: time=0.097 calls=1        <- có index
Trigger for constraint fk_reviews_order: time=17.363 calls=1        <- Seq Scan 300k reviews
Execution Time: 17.695 ms
```

FK được kiểm tra bằng trigger nội bộ, nên chi phí hiện ở dòng `Trigger for constraint`, không phải trong cây plan. Xoá 1,000 đơn → 1,000 lần quét `reviews`. Sửa:

```sql
CREATE INDEX idx_reviews_order_id ON reviews (order_id);
BEGIN;
EXPLAIN (ANALYZE) DELETE FROM orders WHERE id = 250001;     -- fk_reviews_order: time ≈ 0.1 ms
ROLLBACK;
DROP INDEX idx_reviews_order_id;    -- giữ lab ở trạng thái ban đầu
```

`inventory.warehouse_id` thì sao? Chỉ có 5 kho, gần như không bao giờ xoá kho, và mỗi `warehouse_id` khớp ~20% bảng → index gần như vô dụng cho cả lookup. **Không phải FK nào cũng cần index** — quyết định dựa trên việc bảng cha có bị DELETE/UPDATE key hay không và có truy vấn JOIN/lọc theo cột đó không.

---

## 11. Index và replica

Index được tạo trên primary sẽ **tự xuất hiện** trên replica (DDL và nội dung index đều đi qua WAL):

```sql
-- PRIMARY (5432)
CREATE INDEX idx_users_phone ON users (phone);
SELECT pg_current_wal_lsn();

-- REPLICA (5433) - vài ms sau
SELECT indexname FROM pg_indexes WHERE tablename = 'users';
EXPLAIN SELECT * FROM users WHERE phone = '+1-915-884-7227';   -- Index Scan trên replica
CREATE INDEX idx_x ON users (gender);
-- ERROR:  cannot execute CREATE INDEX in a read-only transaction
```

Không thể tạo index "chỉ cho replica" với physical replication — replica là bản sao từng byte của primary. Muốn index khác nhau giữa các node cần logical replication.

`CREATE INDEX CONCURRENTLY` (không khoá ghi trên bảng, dùng cho production):

```sql
DROP INDEX idx_users_phone;
CREATE INDEX CONCURRENTLY idx_users_phone ON users (phone);   -- không chạy được trong BEGIN ... COMMIT
-- nếu bị huỷ giữa chừng, index ở trạng thái INVALID:
SELECT indexrelid::regclass, indisvalid FROM pg_index WHERE NOT indisvalid;
DROP INDEX idx_users_phone;
```

---

## 12. Bài tập tổng hợp

Với mỗi truy vấn: đo plan, đề xuất **một** index (hoặc viết lại query), đo lại, ghi lại kích thước index, rồi `DROP`.

1. Danh sách review mới nhất của một sản phẩm, 20 dòng/trang:
   `SELECT * FROM reviews WHERE product_id = 28148 ORDER BY created_at DESC LIMIT 20;`
2. User VIP: `SELECT id, username FROM users WHERE metadata @> '{"tags": ["vip"]}';`
3. Tồn kho cần nhập của một kho: `SELECT * FROM inventory WHERE warehouse_id = 3 AND quantity - reserved_quantity <= reorder_level;` — `idx_inventory_needs_restock` có được dùng không? Vì sao?
4. Doanh thu theo ngày của tháng trước: `SELECT created_at::date, sum(total_amount) FROM orders WHERE status = 'COMPLETED' AND created_at >= date_trunc('month', now()) - interval '1 month' AND created_at < date_trunc('month', now()) GROUP BY 1 ORDER BY 1;`
5. Tìm sản phẩm theo tên bắt đầu bằng `'Sony'` không phân biệt hoa thường.
6. Đơn có coupon: `SELECT count(*) FROM orders WHERE coupon_code IS NOT NULL;` — B-tree thường, partial `WHERE coupon_code IS NOT NULL`, hay không cần index? (12% số dòng.)

Lời giải tham khảo cho các bài index trong bộ 60 bài: [sql-solutions.md Level 6](sql-solutions.md#level-6--index).
