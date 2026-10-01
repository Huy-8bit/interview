# Query Optimization Lab — đọc EXPLAIN, scan, join, sort, aggregate, statistics

Chạy trên **primary** (`localhost:5432`) hoặc **replica** (`5433`, mọi bài chỉ đọc). Số liệu trong bài đo trên dataset mặc định; máy bạn sẽ khác về thời gian nhưng **loại node và số buffers** gần như giống hệt (cùng `SEED`).

Mục tiêu: nhìn một plan và trả lời được 3 câu — *planner đã chọn gì, vì sao, và ước lượng của nó đúng hay sai.*

Bài liên quan: [index-lab.md](index-lab.md) (tạo index nào), [sql-exercises.md Level 7](sql-exercises.md#level-7--query-optimization-) (bài tập có lời giải).

---

## 0. Đọc EXPLAIN

| Lệnh | Chạy query thật? | Cho biết |
| --- | --- | --- |
| `EXPLAIN q` | không | plan + **ước lượng** (cost, rows) |
| `EXPLAIN (ANALYZE) q` | **có** | thêm thời gian, số dòng **thực tế**, loops |
| `EXPLAIN (ANALYZE, BUFFERS) q` | có | thêm số trang 8 KB đọc: `hit` (shared_buffers), `read` (OS/đĩa), `dirtied`, `written` |
| `EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF) q` | có | gọn hơn để so sánh (bài này dùng nhiều) |
| `EXPLAIN (ANALYZE, BUFFERS, SETTINGS, WAL) q` | có | thêm tham số khác mặc định, lượng WAL sinh ra (với DML) |

⚠️ `EXPLAIN ANALYZE` **thực thi** câu lệnh. Với `INSERT/UPDATE/DELETE` luôn bọc:

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) DELETE FROM orders WHERE id = 1;
ROLLBACK;
```

Giải phẫu một dòng:

```text
Seq Scan on addresses  (cost=0.00..5109.07 rows=159 width=0) (actual time=0.019..17.225 rows=3083 loops=1)
                             ^^^^ ^^^^^^^ ^^^^^^^^ ^^^^^^^           ^^^^^ ^^^^^^ ^^^^^^^^^ ^^^^^^^
                             |    |       |        |                 |     |      |         số lần node chạy
                             |    |       |        byte/dòng ước     |     |      số dòng THẬT (mỗi loop)
                             |    |       số dòng ƯỚC LƯỢNG          |     ms tới khi xong (mỗi loop)
                             |    tổng cost (đơn vị tuỳ ý, ~ trang đọc tuần tự)
                             cost trước khi trả dòng đầu tiên
```

Quy tắc đọc:

1. Đọc **từ trong ra ngoài, từ dưới lên**: node thụt sâu nhất chạy trước, đẩy dòng lên node cha.
2. Thời gian/rows của node có `loops=N` là **trung bình mỗi loop** → tổng = giá trị × N.
3. **Tìm chỗ ước lượng lệch nhiều** (`rows=159` vs `rows=3083`, lệch 19×). Đó thường là gốc của plan tồi: planner chọn Nested Loop vì nghĩ chỉ có vài dòng, thực tế là hàng trăm nghìn.
4. `Rows Removed by Filter` lớn = đọc nhiều rồi vứt đi → ứng viên cho index.
5. `Buffers` ổn định hơn `time`. Chạy 2 lần; lần đầu thường có `read=`, lần sau toàn `hit=`.

Công cụ hình ảnh: DBeaver *Explain Execution Plan* (Ctrl+Shift+E), hoặc dán output text vào [explain.dalibo.com](https://explain.dalibo.com) / [explain.depesz.com](https://explain.depesz.com).

Planner chọn plan bằng **mô hình cost** dựa trên thống kê (`pg_stats`) và tham số:

```sql
SELECT name, setting FROM pg_settings
WHERE name IN ('seq_page_cost', 'random_page_cost', 'cpu_tuple_cost', 'cpu_index_tuple_cost',
               'cpu_operator_cost', 'effective_cache_size', 'work_mem', 'default_statistics_target');
```

---

## 1. Scan: cách đọc một bảng

### 1.1 Seq Scan

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM users WHERE phone = '+1-555-123-4567';
```

```text
Seq Scan on users (actual rows=0 loops=1)
  Filter: ((phone)::text = '+1-555-123-4567'::text)
  Rows Removed by Filter: 100000
  Buffers: shared hit=938 read=4046
Execution Time: 27.978 ms
```

Đọc tuần tự toàn bộ bảng, kiểm tra từng dòng. Lựa chọn **đúng** khi truy vấn lấy phần lớn bảng (`WHERE status = 'COMPLETED'`, 60%) hoặc bảng nhỏ; lựa chọn **tồi** khi chỉ cần vài dòng mà thiếu index (như ở đây).

Bảng lớn còn có **Parallel Seq Scan**: nhiều worker chia nhau các khối (`Workers Launched: 2`, `loops=3` = 2 worker + leader).

### 1.2 Index Scan

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE id = 250000;
```

```text
Index Scan using pk_orders on orders (actual rows=1 loops=1)
  Index Cond: (id = 250000)
  Buffers: shared hit=6 read=1
Execution Time: 0.035 ms
```

Đi xuống cây B-tree (3–4 trang), lấy TID, đọc đúng trang heap chứa dòng. Mỗi dòng = một lần đọc heap ngẫu nhiên → tốt cho **ít dòng**, hoặc khi cần dữ liệu **đã sắp xếp** theo index (`ORDER BY ... LIMIT`).

### 1.3 Index Only Scan

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders WHERE created_at >= now() - interval '7 days';
```

```text
Aggregate (actual rows=1 loops=1)
  ->  Index Only Scan using idx_orders_created_at on orders (actual rows=62392 loops=1)
        Index Cond: (created_at >= (now() - '7 days'::interval))
        Heap Fetches: 0
        Buffers: shared hit=1 read=174
Execution Time: 5.997 ms
```

Mọi cột cần thiết đều có trong index → không cần đọc heap. **Điều kiện**: trang heap phải được đánh dấu *all-visible* (do VACUUM). `Heap Fetches` = số lần vẫn phải đọc heap để kiểm tra MVCC. Đếm 62k dòng chỉ với 175 trang.

**Tự làm**: `SELECT count(*), sum(total_amount) FROM orders WHERE created_at >= now() - interval '7 days';` — còn Index Only Scan không? Vì sao?

### 1.4 Bitmap Index Scan + Bitmap Heap Scan

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE category_id = 12;
```

```text
Bitmap Heap Scan on products (actual rows=1069 loops=1)
  Recheck Cond: (category_id = 12)
  Heap Blocks: exact=943
  Buffers: shared hit=198 read=747
  ->  Bitmap Index Scan on idx_products_category_id (actual rows=1069 loops=1)
        Index Cond: (category_id = 12)
Execution Time: 4.112 ms
```

Hai pha: (1) quét index, gom TID thành **bitmap theo trang**; (2) đọc các trang heap theo **thứ tự vật lý**, mỗi trang đúng một lần. Ở giữa Index Scan (vài dòng) và Seq Scan (đa số bảng). Ưu điểm phụ: kết hợp nhiều index bằng `BitmapAnd` / `BitmapOr`.

- `Heap Blocks: exact=N` — bitmap đủ chi tiết tới từng dòng.
- `Heap Blocks: lossy=N` — bitmap vượt `work_mem` nên chỉ nhớ "trang nào", phải `Recheck` mọi dòng trong trang (`Rows Removed by Index Recheck`).

So sánh với cùng bộ lọc nhưng **ít** dòng hơn (user có 3 đơn → Index Scan) và **nhiều** dòng hơn:

```sql
EXPLAIN SELECT * FROM orders WHERE user_id = 1234;                          -- Index Scan
EXPLAIN SELECT * FROM products WHERE category_id IN (12, 13, 14, 15);       -- Bitmap Heap Scan
EXPLAIN SELECT * FROM products WHERE category_id BETWEEN 2 AND 40;          -- Seq Scan
```

### 1.5 Ép planner dùng cách khác để so sánh

Các tham số `enable_*` không cấm hẳn mà chỉ cộng một cost khổng lồ; dùng để **thí nghiệm**, không dùng trên production:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE category_id = 12;   -- Bitmap Heap Scan

SET enable_bitmapscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE category_id = 12;   -- Index Scan: nhiều buffer hơn?
SET enable_indexscan = off;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM products WHERE category_id = 12;   -- Seq Scan
RESET enable_bitmapscan; RESET enable_indexscan;
```

Ghi lại `cost` ước lượng và `Execution Time` thực của cả 3. Planner có chọn đúng phương án nhanh nhất không?

---

## 2. Join: cách nối hai tập dòng

| Join | Cách làm | Tốt khi | Chi phí |
| --- | --- | --- | --- |
| **Nested Loop** | với mỗi dòng bên ngoài, tìm dòng khớp bên trong (thường bằng index) | bên ngoài **ít dòng**, bên trong có index | O(N × lookup) |
| **Hash Join** | build hash table từ bảng nhỏ, quét bảng lớn và probe | hai tập lớn, điều kiện `=` | bộ nhớ `work_mem × hash_mem_multiplier` |
| **Merge Join** | hai đầu vào đã **sắp xếp** theo khoá join, đi song song | cả hai đã có thứ tự (index), hoặc kết quả cần thứ tự đó | sort nếu chưa có thứ tự |

### 2.1 Nested Loop

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.order_number, p.name, i.quantity
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.id = 250000;
```

```text
Nested Loop (actual rows=1 loops=1)
  ->  Nested Loop (actual rows=1 loops=1)
        ->  Index Scan using pk_orders on orders o (actual rows=1 loops=1)
              Index Cond: (id = 250000)
        ->  Index Scan using idx_order_items_order_id on order_items i (actual rows=1 loops=1)
              Index Cond: (order_id = 250000)
  ->  Index Scan using pk_products on products p (actual rows=1 loops=1)
        Index Cond: (id = i.product_id)
Execution Time: 0.041 ms
```

Với nhiều dòng bên ngoài, chú ý `loops`:

```sql
EXPLAIN (ANALYZE)
SELECT o.id, o.created_at, i.product_id, i.quantity
FROM orders o JOIN order_items i ON i.order_id = o.id
WHERE o.user_id = 55368;
```

```text
Nested Loop (actual rows=99 loops=1)
  ->  Index Scan using idx_orders_user_id on orders o (actual rows=36 loops=1)
  ->  Index Scan using idx_order_items_order_id on order_items i (actual rows=3 loops=36)
```

Inner index scan chạy **36 lần**, mỗi lần trả trung bình 3 dòng → 99–108 dòng tổng.

Ép bỏ Nested Loop để thấy vì sao nó được chọn:

```sql
SET enable_nestloop = off;
EXPLAIN (ANALYZE) SELECT o.order_number, p.name, i.quantity
FROM orders o JOIN order_items i ON i.order_id = o.id JOIN products p ON p.id = i.product_id
WHERE o.id = 250000;
RESET enable_nestloop;
```

```text
Hash Join ...
  ->  Seq Scan on products p (actual rows=100000 loops=1)     <- đọc 100k sản phẩm để lấy 1
Execution Time: 146.355 ms                                     <- chậm hơn ~3,500 lần
```

### 2.2 Hash Join

```sql
SET max_parallel_workers_per_gather = 0;     -- tắt parallel cho plan dễ đọc
EXPLAIN (ANALYZE, BUFFERS)
SELECT c.name, sum(i.total_price) AS revenue
FROM order_items i
JOIN products p   ON p.id = i.product_id
JOIN categories c ON c.id = p.category_id
GROUP BY c.name ORDER BY revenue DESC LIMIT 5;
RESET max_parallel_workers_per_gather;
```

```text
Limit (actual rows=5 loops=1)
  ->  Sort (actual rows=5 loops=1)
        Sort Key: (sum(i.total_price)) DESC
        Sort Method: top-N heapsort  Memory: 25kB
        ->  HashAggregate (actual rows=40 loops=1)
              Group Key: c.name
              ->  Hash Join (actual rows=1499494 loops=1)
                    Hash Cond: (p.category_id = c.id)
                    ->  Hash Join (actual rows=1499494 loops=1)
                          Hash Cond: (i.product_id = p.id)
                          ->  Seq Scan on order_items i (actual rows=1499494 loops=1)
                          ->  Hash (actual rows=100000 loops=1)
                                Buckets: 131072  Batches: 1  Memory Usage: 5321kB
                                ->  Seq Scan on products p (actual rows=100000 loops=1)
                    ->  Hash (actual rows=50 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 11kB
                          ->  Seq Scan on categories c (actual rows=50 loops=1)
Execution Time: 393.472 ms
```

- Node `Hash` (bảng nhỏ hơn) được build **trước**, sau đó bảng lớn được quét và probe.
- `Batches: 1` = hash table vừa trong bộ nhớ. `Batches > 1` = tràn ra đĩa → giảm `work_mem` để thấy: `SET work_mem = '256kB';` rồi chạy lại, quan sát `Batches` và thời gian.
- Ở đây Seq Scan là **đúng**: cần mọi dòng `order_items`, index chẳng giúp gì.

### 2.3 Merge Join

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, sum(i.total_price)
FROM orders o JOIN order_items i ON i.order_id = o.id
WHERE o.id BETWEEN 100000 AND 200000
GROUP BY o.id;
```

```text
GroupAggregate (actual rows=100001 loops=1)
  Group Key: o.id
  ->  Merge Join (actual rows=300367 loops=1)
        Merge Cond: (o.id = i.order_id)
        ->  Index Only Scan using pk_orders on orders o (actual rows=100001 loops=1)
              Index Cond: ((id >= 100000) AND (id <= 200000))
        ->  Index Scan using idx_order_items_order_id on order_items i (actual rows=600477 loops=1)
Execution Time: 90.906 ms
```

Cả hai bên đều có index trên khoá join → đã có thứ tự → Merge Join không cần sort, và output đã theo `o.id` nên `GroupAggregate` dùng được luôn (không cần hash).

Câu hỏi: bên `order_items` đọc **600,477** dòng nhưng chỉ 300,367 dòng khớp. Vì sao? (Gợi ý: điều kiện `BETWEEN` chỉ áp lên `o.id`; Merge Join đọc `order_items` từ đầu theo `order_id` cho tới khi vượt `200000`. Thử thêm `AND i.order_id BETWEEN 100000 AND 200000` — planner có tự suy ra điều này không?)

### 2.4 Anti join và semi join

```sql
-- user chưa từng đặt hàng
EXPLAIN (ANALYZE) SELECT count(*) FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
-- -> Parallel Hash Right Anti Join ... 12,283 user

EXPLAIN SELECT count(*) FROM users WHERE id NOT IN (SELECT user_id FROM orders);
-- -> Filter: (NOT (hashed SubPlan 1))
```

`NOT EXISTS` thành **Anti Join** (tối ưu được mọi kiểu join). `NOT IN` thành *hashed SubPlan* — chấp nhận được ở đây, nhưng nếu subquery quá lớn để hash trong `work_mem` thì thành *plain SubPlan* chạy lại cho **từng dòng**. Và nguy hiểm hơn về **ngữ nghĩa**: chỉ cần subquery trả về một `NULL`, `NOT IN` trả về 0 dòng:

```sql
SELECT count(*) FROM users WHERE id NOT IN (SELECT user_id FROM orders UNION ALL SELECT NULL);   -- 0 !
```

Quy tắc: dùng `NOT EXISTS`, không dùng `NOT IN (subquery)`.

---

## 3. Sort

```sql
SET work_mem = '4MB';
EXPLAIN (ANALYZE) SELECT * FROM orders ORDER BY total_amount DESC;
EXPLAIN (ANALYZE) SELECT * FROM orders ORDER BY total_amount DESC LIMIT 100;
SET work_mem = '256MB';
EXPLAIN (ANALYZE) SELECT * FROM orders ORDER BY total_amount DESC;
RESET work_mem;
```

| Truy vấn | work_mem | Sort Method | Thời gian |
| --- | --- | --- | --- |
| 500k dòng | 4MB | `external merge  Disk: 52160kB` (×3 worker) | 188 ms |
| `LIMIT 100` | 4MB | `top-N heapsort  Memory: 113kB` | 20 ms |
| 500k dòng | 256MB | `quicksort  Memory: 166368kB` | 191 ms |

- **external merge**: dữ liệu không vừa `work_mem` → ghi các đoạn đã sort ra file tạm rồi merge. Log server ghi lại (lab đặt `log_temp_files = 10MB`): `docker compose logs postgres-primary | grep temporary`.
- **top-N heapsort**: có `LIMIT` → chỉ giữ N dòng tốt nhất trong heap, không cần sort cả tập.
- **quicksort**: vừa bộ nhớ. Ở đây không nhanh hơn external merge vì có parallel và đĩa SSD — nhưng tốn 166 MB RAM **cho một node của một query**. `work_mem` áp dụng cho **mỗi** node sort/hash của **mỗi** session → 100 connection × vài node × 256MB = hết RAM. Đó là lý do mặc định nhỏ.
- **Sort tránh được hoàn toàn** khi có index đúng thứ tự: `ORDER BY created_at DESC LIMIT 20` → `Index Scan Backward using idx_orders_created_at`, không có node Sort.

**Incremental Sort** — dữ liệu đã sắp theo một phần khoá:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_number, created_at FROM orders
ORDER BY created_at DESC, id DESC LIMIT 20;
```

```text
Limit
  ->  Incremental Sort
        Sort Key: created_at DESC, id DESC
        Presorted Key: created_at
        ->  Index Scan Backward using idx_orders_created_at on orders
```

Index đã cho thứ tự `created_at`; chỉ cần sort trong từng nhóm `created_at` bằng nhau (rất nhỏ).

---

## 4. Aggregate

| Node | Khi nào |
| --- | --- |
| `Aggregate` | không có `GROUP BY` (`count(*)`, `sum(...)` trên toàn tập) |
| `HashAggregate` | `GROUP BY`, input chưa sắp xếp, số nhóm vừa `work_mem` |
| `GroupAggregate` | `GROUP BY`, input **đã sắp xếp** theo khoá nhóm (từ index, Merge Join, hoặc Sort) |
| `Partial ... → Gather → Finalize ...` | aggregate song song: mỗi worker tính một phần, leader gộp lại |
| `GroupAggregate` nhiều `Group Key` / `MixedAggregate` | `GROUPING SETS` / `ROLLUP` / `CUBE` (sort một lần, tính nhiều mức nhóm; `MixedAggregate` khi kết hợp hash + sort) |

```sql
-- HashAggregate: ít nhóm (37 tháng), input từ Index Only Scan
EXPLAIN SELECT date_trunc('month', created_at) AS month, count(*) FROM orders GROUP BY 1;

-- GroupAggregate: input đã sắp xếp theo user_id từ index
EXPLAIN SELECT user_id, count(*) FROM orders GROUP BY user_id;

-- Parallel: Finalize HashAggregate <- Gather <- Partial HashAggregate
EXPLAIN (ANALYZE)
SELECT u.metadata ->> 'signup_source' AS source, count(*)
FROM orders o JOIN users u ON u.id = o.user_id
GROUP BY 1;

-- ROLLUP: tổng theo (năm, status), theo năm, và tổng cộng trong một lần quét
EXPLAIN (ANALYZE)
SELECT extract(year FROM created_at) AS year, status, count(*), sum(total_amount)
FROM orders GROUP BY ROLLUP (1, 2) ORDER BY 1, 2;
```

`HashAggregate` vượt `work_mem` sẽ hiện `Batches: N  Disk Usage: ...` (PG13+). Thử với `SET work_mem = '64kB';` trên truy vấn `GROUP BY user_id`.

---

## 5. Statistics: khi planner đoán sai

Planner ước lượng số dòng từ `pg_stats` (cập nhật bởi `ANALYZE` / autovacuum):

```sql
SELECT attname, null_frac, n_distinct, most_common_vals, most_common_freqs, correlation
FROM pg_stats WHERE tablename = 'addresses' AND attname IN ('country_code', 'city');
```

### 5.1 Cột tương quan

Mặc định planner giả định các điều kiện **độc lập**: P(VN ∧ Hanoi) = P(VN) × P(Hanoi). Nhưng "Hanoi" thì luôn là VN:

```sql
EXPLAIN ANALYZE SELECT count(*) FROM addresses WHERE country_code = 'VN' AND city = 'Hanoi';
```

```text
Seq Scan on addresses  (cost=0.00..5109.07 rows=159 width=0) (actual time=0.019..17.225 rows=3083 loops=1)
```

Ước **159**, thực tế **3,083** (lệch 19×). Ở truy vấn đơn lẻ không sao; nhưng nếu đây là bên ngoài của một join, planner sẽ chọn Nested Loop cho "159 dòng" trong khi thực tế phải lặp 3,083 lần. Sửa bằng **extended statistics**:

```sql
CREATE STATISTICS st_addresses_country_city (dependencies, mcv) ON country_code, city FROM addresses;
ANALYZE addresses;
EXPLAIN ANALYZE SELECT count(*) FROM addresses WHERE country_code = 'VN' AND city = 'Hanoi';
-- Seq Scan on addresses  (cost=0.00..5109.07 rows=2977 width=0) (actual ... rows=3083 loops=1)

SELECT statistics_name, attnames, dependencies FROM pg_stats_ext WHERE tablename = 'addresses';
DROP STATISTICS st_addresses_country_city;
ANALYZE addresses;
```

### 5.2 Thống kê cũ

```sql
-- PRIMARY. Sinh 200k đơn PENDING "mới" (trong transaction, rồi ROLLBACK)
BEGIN;
INSERT INTO orders (user_id, order_number, status, subtotal, total_amount, shipping_address, created_at)
SELECT 1 + g % 100000, 'TMP-' || g, 'PENDING', 10, 10, '{}', now()
FROM generate_series(1, 200000) g;

EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PENDING' AND created_at > now() - interval '1 hour';

ANALYZE orders;     -- ANALYZE chạy được trong transaction và thấy dòng chưa commit của chính nó
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PENDING' AND created_at > now() - interval '1 hour';
ROLLBACK;
ANALYZE orders;
```

```text
-- trước ANALYZE
Index Scan using idx_orders_open_created_at on orders  (cost=0.42..6.00 rows=21 width=309) (actual rows=200170 loops=1)
-- sau ANALYZE
Index Scan using idx_orders_open_created_at on orders  (cost=0.43..5543.10 rows=62749 width=251) (actual rows=200170 loops=1)
```

Ước **21** dòng trong khi thực tế **200,170** (lệch ~10,000×): histogram `created_at` cũ không có giá trị nào trong giờ vừa qua. Plan ở đây vẫn giữ nguyên, nhưng nếu kết quả này được join tiếp, một ước lượng "21 dòng" sẽ dẫn tới Nested Loop chạy 200k lần. Đây là lý do sau mỗi đợt nạp dữ liệu lớn (ETL, restore) phải chạy `ANALYZE` — generator của lab làm việc này ở bước cuối, `scripts/restore.sh` cũng vậy.

### 5.3 Độ chi tiết thống kê

```sql
-- user_id có 87k giá trị khác nhau; mặc định chỉ lấy mẫu 30,000 dòng và lưu 100 giá trị phổ biến nhất
SELECT n_distinct, array_length(most_common_vals::text::text[], 1) AS n_mcv
FROM pg_stats WHERE tablename = 'orders' AND attname = 'user_id';

-- trên lab: n_distinct = 41865 (ước lượng từ mẫu), n_mcv = 13
SELECT count(DISTINCT user_id) FROM orders;     -- thực tế: 87717

ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS 1000;
ANALYZE orders;
-- chạy lại truy vấn trên: n_distinct chính xác hơn? n_mcv?
ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS -1;    -- về mặc định
ANALYZE orders;
```

---

## 6. Viết lại truy vấn (sargable)

Một điều kiện là *sargable* (Search ARGument ABLE) khi cột đứng **một mình** ở một vế, để index trên cột đó dùng được.

```sql
-- KHÔNG sargable: hàm/ép kiểu bọc quanh cột
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE created_at::date = current_date - 1;

-- Sargable: khoảng nửa mở
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE created_at >= current_date - 1 AND created_at < current_date;
```

| | Plan | Buffers | Thời gian |
| --- | --- | --- | --- |
| `created_at::date = ...` | Parallel Index Only Scan **toàn bộ index**, `Filter`, `Rows Removed by Filter: 164148` ×3 | 1,372 | 41 ms |
| `created_at >= ... AND < ...` | Index Only Scan, `Index Cond` | 28 | 0.56 ms |

Các mẫu tương tự:

| Không sargable | Sargable |
| --- | --- |
| `WHERE date_trunc('month', created_at) = '2025-03-01'` | `WHERE created_at >= '2025-03-01' AND created_at < '2025-04-01'` |
| `WHERE extract(year FROM created_at) = 2025` | `WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01'` |
| `WHERE price * 1.1 > 100` | `WHERE price > 100 / 1.1` |
| `WHERE lower(email) = ...` khi chỉ có index trên `email` | tạo expression index `lower(email)` (đã có) |
| `WHERE coalesce(phone, '') = '...'` | `WHERE phone = '...'` |
| `WHERE id::text = '123'` | `WHERE id = 123` |

---

## 7. Phân trang: OFFSET vs keyset

```sql
-- OFFSET: trang 5001 (20 dòng/trang)
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_number, created_at FROM orders
ORDER BY created_at DESC OFFSET 100000 LIMIT 20;
```

```text
Limit (actual rows=20 loops=1)
  Buffers: shared hit=4554
  ->  Index Scan Backward using idx_orders_created_at on orders (actual rows=100020 loops=1)
Execution Time: 10.411 ms
```

Đọc **100,020** dòng để trả 20. Trang càng sâu càng chậm (tuyến tính).

```sql
-- KEYSET (seek): nhớ giá trị cuối của trang trước, đi tiếp từ đó
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_number, created_at FROM orders
WHERE created_at < '2025-06-01 12:34:56+00'          -- created_at của dòng cuối trang trước
ORDER BY created_at DESC LIMIT 20;
```

```text
Limit (actual rows=20 loops=1)
  Buffers: shared hit=8 read=3
  ->  Index Scan Backward using idx_orders_created_at on orders (actual rows=20 loops=1)
        Index Cond: (created_at < ...)
Execution Time: 0.080 ms
```

Thời gian **không phụ thuộc** trang thứ mấy. Nhược điểm: không nhảy thẳng tới "trang 5001" được, chỉ "trang tiếp theo".

**Tự làm**: nếu hai đơn có cùng `created_at` thì keyset ở trên có thể bỏ sót dòng. Dùng so sánh **row value** với khoá phụ duy nhất:

```sql
SELECT id, order_number, created_at FROM orders
WHERE (created_at, id) < ('2025-06-01 12:34:56+00', 123456)
ORDER BY created_at DESC, id DESC LIMIT 20;
```

Plan hiện tại có `Incremental Sort` (mục 3). Index nào làm nó biến mất? Đo trước/sau.

---

## 8. Một quy trình tối ưu

1. Lấy truy vấn chậm thật (từ `pg_stat_statements`, xem [monitoring.md](monitoring.md#4-truy-vấn-tốn-tài-nguyên-nhất-pg_stat_statements), hoặc log `log_min_duration_statement = 1s`).
2. `EXPLAIN (ANALYZE, BUFFERS)` — chạy 2 lần.
3. Tìm node tốn **nhiều thời gian riêng** nhất (thời gian node − thời gian các con) và nhiều buffers nhất.
4. So **rows ước lượng vs thực tế** ở từng node; lệch > 10× → thống kê (ANALYZE, `SET STATISTICS`, `CREATE STATISTICS`) hoặc điều kiện không sargable.
5. `Rows Removed by Filter` lớn → thiếu index hoặc index sai thứ tự cột.
6. `Sort` / `Hash` tràn đĩa → index đúng thứ tự, giảm số dòng sớm hơn, hoặc tăng `work_mem` **cho session đó** (`SET LOCAL work_mem = '64MB'` trong transaction).
7. Sửa **một** thứ, đo lại, ghi lại kết quả. Không đoán.

---

## 9. Bài tập

Với mỗi truy vấn: ghi plan, node đắt nhất, chỗ ước lượng lệch, đề xuất và kết quả sau khi sửa.

1. Top 10 khách hàng theo doanh thu năm nay:

   ```sql
   SELECT u.id, u.username, sum(o.total_amount) AS revenue
   FROM users u JOIN orders o ON o.user_id = u.id
   WHERE o.status = 'COMPLETED' AND extract(year FROM o.created_at) = extract(year FROM now())
   GROUP BY u.id, u.username ORDER BY revenue DESC LIMIT 10;
   ```

2. Rating trung bình của 20 sản phẩm bán chạy nhất trong 30 ngày qua (join `order_items` → `orders` → `reviews`). Quan sát join order planner chọn.

3. Với mỗi user, đơn hàng gần nhất (`DISTINCT ON (user_id) ... ORDER BY user_id, created_at DESC`) vs `LATERAL (... LIMIT 1)` vs window `row_number()`. Cái nào nhanh nhất khi lấy cho **tất cả** user? Khi chỉ lấy cho **100** user?

4. `SELECT * FROM orders WHERE shipping_address ->> 'city' = 'Hanoi';` — chọn giữa expression index B-tree và GIN; kích thước mỗi loại.

5. `SELECT count(DISTINCT user_id) FROM orders WHERE created_at >= now() - interval '90 days';` — so với `SELECT count(*) FROM (SELECT DISTINCT user_id ...) s;`.

6. Chạy bài 1 trên **replica** (`5433`). Plan có giống primary không? (Gợi ý: thống kê `pg_statistic` cũng được replicate.) `pg_stat_statements` của replica có ghi lại không?
