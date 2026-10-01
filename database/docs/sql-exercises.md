# Bài tập SQL — 60 bài, 10 level

Chạy trên **primary** (`localhost:5432`, database `ecommerce`). Các bài chỉ đọc (Level 1–5) chạy được cả trên replica (`5433`).
Lời giải: [sql-solutions.md](sql-solutions.md) — hãy tự làm trước.

Quy ước:

- Tiền tệ là USD, cột kiểu `numeric(12,2)`.
- "Doanh thu" = `orders.total_amount` của đơn `COMPLETED`, trừ khi đề nói khác.
- "Hôm nay" = `now()`; dữ liệu trải dài ~3 năm tới thời điểm sinh dữ liệu.
- Bài có ký hiệu 🔍 yêu cầu chạy `EXPLAIN (ANALYZE, BUFFERS)` và giải thích plan.
- Bài có ký hiệu 👥 cần **2 session** (2 connection DBeaver/psql) — xem cách làm ở [transaction-lab.md](transaction-lab.md).
- Bài làm thay đổi dữ liệu: bọc trong `BEGIN; ... ROLLBACK;` nếu không muốn giữ thay đổi.

Làm quen với schema trước:

```sql
\dt                -- psql: danh sách bảng (DBeaver: Database Navigator)
\d orders          -- cấu trúc bảng, index, constraint
SELECT * FROM orders LIMIT 5;
```

---

## Level 1 — Basic SQL

**1.1** Liệt kê 10 sản phẩm đang bán (`status = 'ACTIVE'`) đắt nhất: `id, sku, name, brand, price`.

**1.2** Đếm số user theo từng `status`, sắp xếp giảm dần theo số lượng. Tính thêm phần trăm của mỗi status.

**1.3** Liệt kê user đăng ký trong 30 ngày gần nhất (`id, username, email, created_at`), mới nhất trước. Có bao nhiêu người?

**1.4** Tìm các sản phẩm thương hiệu `Apple` có giá dưới 500 USD, sắp xếp theo giá tăng dần. Hiển thị thêm cột `margin = price - cost` và `margin_pct` (làm tròn 1 chữ số).

**1.5** Có bao nhiêu user **không có** số điện thoại? Vì sao `WHERE phone = NULL` trả về 0 dòng?

**1.6** Dữ liệu JSONB và mảng:
  a) Đếm user có `metadata->>'preferred_language' = 'vi'`.
  b) Liệt kê 10 sản phẩm có tag `bestseller` (cột `tags text[]`).
  c) Đếm sản phẩm điện thoại (`attributes->'specs'->>'storage_gb'`) có bộ nhớ ≥ 512 GB.

## Level 2 — JOIN

**2.1** 10 đơn hàng mới nhất kèm `username`, `email` của người đặt.

**2.2** Mỗi sản phẩm kèm tên danh mục và tên danh mục cha (`categories` tự tham chiếu). Chỉ lấy 20 dòng đầu, dạng `Electronics > Smartphones`.

**2.3** Có bao nhiêu user **chưa từng đặt hàng**? Viết bằng 2 cách: `LEFT JOIN ... IS NULL` và `NOT EXISTS`. So sánh plan.

**2.4** Chi tiết đơn hàng `id = 250000`: tên sản phẩm, số lượng, đơn giá, giảm giá, thành tiền; thêm dòng kiểm tra tổng các dòng = `orders.subtotal`.

**2.5** Đếm số sản phẩm **chưa bán được cái nào**, nhóm theo danh mục cấp cao nhất (top-level).

**2.6** Với mỗi kho (`warehouses`), đếm số dòng tồn kho cần nhập thêm (`quantity - reserved_quantity <= reorder_level`) và tổng số lượng khả dụng.

## Level 3 — Aggregation

**3.1** Số đơn, tổng doanh thu và giá trị đơn trung bình theo từng `status`.

**3.2** Doanh thu theo tháng của đơn `COMPLETED` trong 12 tháng gần nhất.

**3.3** Top 10 sản phẩm bán chạy nhất theo **số lượng** (đơn không bị `CANCELLED`): tên, tổng số lượng, doanh thu.

**3.4** Với mỗi danh mục lá: số sản phẩm, giá min / max / trung bình / trung vị (`percentile_cont`). Chỉ giữ danh mục có hơn 2000 sản phẩm.

**3.5** Theo phương thức thanh toán (chỉ payment `SUCCEEDED`): số giao dịch, tổng tiền, trung bình. Dùng `FILTER` để thêm cột: số giao dịch > 500 USD.

**3.6** Sản phẩm có ít nhất 100 review và điểm trung bình ≥ 4.3: tên, số review, điểm TB, tỷ lệ review 5★, tỷ lệ verified purchase.

## Level 4 — Subquery / CTE

**4.1** Sản phẩm `ACTIVE` có giá cao hơn **giá trung bình của chính danh mục đó**. Đếm theo danh mục. Viết bằng correlated subquery trước — chạy `EXPLAIN` (chưa `ANALYZE`!) và ước đoán nó chạy bao lâu — rồi viết lại cho nhanh.

**4.2** Dùng CTE: khách hàng có tổng chi tiêu (đơn `COMPLETED`) > 5,000 USD — username, số đơn, tổng chi, ngày mua gần nhất. Sắp xếp theo tổng chi.

**4.3** User đã mua **cả** sản phẩm danh mục `Laptops` **và** `Smartphones` (bất kỳ đơn nào không bị huỷ). Đếm số user.

**4.4** Recursive CTE: in cây danh mục với đường dẫn đầy đủ (`Electronics > Laptops`), độ sâu và số sản phẩm trực tiếp.

**4.5** Kiểm tra toàn vẹn dữ liệu:
  a) Đơn có `subtotal` ≠ tổng `order_items.total_price` (phải = 0).
  b) Sản phẩm có `stock_quantity` ≠ tổng `inventory.quantity`.
  c) Đơn `COMPLETED` không có payment `SUCCEEDED`.

**4.6** Cohort: với mỗi user lấy đơn **đầu tiên** (`DISTINCT ON`), rồi đếm số khách mới theo tháng của đơn đầu tiên trong 12 tháng gần nhất.

## Level 5 — Window Function

**5.1** Top 3 sản phẩm đắt nhất trong mỗi danh mục lá. So sánh `ROW_NUMBER`, `RANK`, `DENSE_RANK` khi có giá bằng nhau.

**5.2** Doanh thu theo ngày trong 30 ngày gần nhất kèm **lũy kế** (running total).

**5.3** Với user `55368`: liệt kê các đơn và số ngày kể từ đơn trước (`LAG`), cùng số thứ tự đơn.

**5.4** Tăng trưởng doanh thu tháng so với tháng trước (MoM %) trong 24 tháng gần nhất.

**5.5** Kiểm chứng "20% khách hàng tạo ra ~70% đơn hàng": chia user có đơn thành 5 nhóm bằng `NTILE(5)` theo số đơn, tính tỷ trọng mỗi nhóm. Làm tương tự với doanh thu sản phẩm (top 1% sản phẩm chiếm bao nhiêu % số lượng bán?).

**5.6** Trung bình trượt 7 ngày (7-day moving average) số đơn mỗi ngày trong 60 ngày gần nhất. Giải thích khác biệt giữa `ROWS` và `RANGE`.

## Level 6 — Index 🔍

**6.1** Chạy `SELECT * FROM users WHERE email = '<một email có thật>';`. Vì sao Seq Scan dù có index `ux_users_email_lower`? Viết lại để dùng index. Có nên tạo thêm index trên `email`?

**6.2** Tìm user theo số điện thoại. So sánh plan/time/buffers trước và sau khi tạo index. Kích thước index là bao nhiêu?

**6.3** Với index `idx_orders_status_created_at (status, created_at)`, plan thay đổi thế nào cho 3 truy vấn: lọc cả `status` và `created_at`; chỉ `created_at`; chỉ `status`? Giải thích nguyên tắc *leftmost prefix*.

**6.4** Tìm payment `PENDING` được tạo cách đây hơn 1 ngày. Tạo **partial index** phù hợp và so sánh kích thước với index đầy đủ trên `(status, created_at)`.

**6.5** Tổng số lượng bán của sản phẩm `id = X` (chọn một sản phẩm bán chạy). Tạo **covering index** để có Index Only Scan; quan sát `Heap Fetches`.

**6.6** Viết truy vấn tìm: (a) index thừa (prefix của index khác), (b) foreign key **không có index**. Chứng minh FK không index làm `DELETE FROM orders WHERE id = ...` chậm.

## Level 7 — Query Optimization 🔍

**7.1** Tối ưu truy vấn:

```sql
SELECT * FROM orders WHERE user_id = 55368 AND status = 'COMPLETED' ORDER BY created_at DESC;
```

(Chi tiết từng bước: [index-lab.md §3.1](index-lab.md#31-bài-tập-tối-ưu-truy-vấn-đơn-hàng-của-tôi); cách đọc plan: [query-optimization-lab.md](query-optimization-lab.md).)

**7.2** Phân trang: lấy trang thứ 5000 (20 dòng/trang) của danh sách đơn mới nhất bằng `OFFSET`, rồi bằng **keyset pagination**. So sánh.

**7.3** Đếm đơn của ngày hôm qua bằng `WHERE created_at::date = current_date - 1` và `WHERE date_trunc('day', created_at) = ...`. Vì sao không dùng index? Viết lại *sargable*.

**7.4** Tìm user theo `lower(email) = ?` **hoặc** `phone = ?` (sau khi đã có index phone ở 6.2). Quan sát `BitmapOr`. Viết lại bằng `UNION`.

**7.5** Ước lượng sai do cột tương quan: `SELECT count(*) FROM addresses WHERE country_code = 'VN' AND city = 'Hanoi';`. So sánh `rows` ước lượng và thực tế; dùng `CREATE STATISTICS` để sửa.

**7.6** `SELECT * FROM orders ORDER BY total_amount DESC` (không LIMIT) với `work_mem` 4MB vs 256MB: plan, `Sort Method`, thời gian. Sau đó thêm `LIMIT 100` — Sort Method đổi thành gì?

## Level 8 — Transaction 👥

**8.1** Viết transaction đặt hàng hoàn chỉnh cho user 42: tạo order, 2 order_items, payment, trừ tồn kho — tất cả hoặc không gì cả. Cố tình làm một bước vi phạm CHECK constraint và quan sát rollback.

**8.2** Dùng `SAVEPOINT` để khi một dòng hàng lỗi thì chỉ bỏ dòng đó, vẫn commit phần còn lại.

**8.3** 👥 READ COMMITTED: chứng minh *non-repeatable read* (cùng câu SELECT trong một transaction ra 2 kết quả khác nhau).

**8.4** 👥 REPEATABLE READ: chứng minh snapshot không đổi, và lỗi `could not serialize access due to concurrent update` khi hai session cùng UPDATE một dòng.

**8.5** 👥 SERIALIZABLE: tạo tình huống *write skew* (hai session cùng đọc – cùng ghi dựa trên điều kiện chung) bị chặn ở SERIALIZABLE nhưng lọt ở REPEATABLE READ.

**8.6** 👥 *Lost update*: hai session "đọc số lượng tồn → tính trong app → ghi lại" làm mất một lần trừ kho. Sửa bằng (a) UPDATE nguyên tử, (b) `SELECT ... FOR UPDATE`, (c) optimistic locking với cột version/`updated_at`.

## Level 9 — Locking 👥

**9.1** 👥 Session A `SELECT ... FOR UPDATE` một dòng inventory, session B UPDATE dòng đó. Từ session thứ 3, tìm ai chặn ai bằng `pg_blocking_pids` và `pg_locks`.

**9.2** Hàng đợi công việc: nhiều worker cùng lấy payment `PENDING` để xử lý mà không đụng nhau — dùng `FOR UPDATE SKIP LOCKED`.

**9.3** 👥 `NOWAIT` và `lock_timeout`: thay vì chờ, báo lỗi ngay / sau 2 giây.

**9.4** 👥 Tạo **deadlock** bằng 2 session cập nhật 2 dòng theo thứ tự ngược nhau. Đọc thông báo lỗi và log server; sửa bằng thứ tự khoá nhất quán.

**9.5** 👥 Lock queue: session A mở transaction đọc `products`; session B `ALTER TABLE products ADD COLUMN ...`; session C `SELECT` products. Vì sao C cũng bị treo? Cách chạy DDL an toàn (`lock_timeout`, `CREATE INDEX CONCURRENTLY`).

**9.6** Advisory lock: đảm bảo một job báo cáo chỉ chạy một instance tại một thời điểm (`pg_try_advisory_lock`).

## Level 10 — PostgreSQL Internals

**10.1** Xem `xmin, xmax, ctid` của một sản phẩm trước/sau UPDATE; UPDATE đó có phải **HOT** không? Kiểm chứng bằng `pg_stat_user_tables.n_tup_hot_upd`.

**10.2** Dùng `pageinspect` xem các tuple trong block 0 của bảng `replication_test` sau khi INSERT, UPDATE, DELETE vài dòng. Giải thích `lp_flags`, `t_xmin`, `t_xmax`, `t_ctid`.

**10.3** Tạo dead tuple: cập nhật 50,000 dòng `orders`, xem `n_dead_tup`, `pgstattuple`, rồi `VACUUM` / `VACUUM FULL`; so sánh kích thước bảng.

**10.4** Visibility map: sau khi UPDATE nhiều dòng `orders`, chạy lại query Index Only Scan ở bài 6.5 / trên `idx_orders_created_at` — `Heap Fetches` thay đổi thế nào? Sau `VACUUM`?

**10.5** WAL: đo lượng WAL sinh ra khi UPDATE 10,000 dòng, trước và ngay sau một `CHECKPOINT` (full page writes). Dùng `pg_walinspect.pg_get_wal_stats`.

**10.6** Lưu trữ vật lý: tìm file dữ liệu của bảng `orders` (`pg_relation_filepath`), bảng TOAST của `reviews`, và tuổi transaction (`age(datfrozenxid)`) của các database — giải thích *transaction ID wraparound*.
