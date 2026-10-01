# MVCC Lab — xmin, xmax, ctid, tuple version, VACUUM

**MVCC (Multi-Version Concurrency Control)**: PostgreSQL không ghi đè dữ liệu tại chỗ. Mỗi `UPDATE` tạo một **phiên bản mới** của dòng (tuple), phiên bản cũ vẫn nằm trên đĩa cho tới khi VACUUM dọn. Mỗi transaction nhìn dữ liệu qua một **snapshot** và chỉ thấy các phiên bản "hợp lệ" với snapshot đó. Kết quả: *reader không chặn writer, writer không chặn reader*.

Chạy trên **primary** (`localhost:5432`).

## 1. Các cột hệ thống

Mọi bảng có các cột ẩn:

| Cột | Ý nghĩa |
| --- | --- |
| `xmin` | XID của transaction đã **tạo** phiên bản này (INSERT hoặc UPDATE) |
| `xmax` | XID của transaction đã **xoá / thay thế / khoá** phiên bản này; `0` = còn "sống" |
| `ctid` | Vị trí vật lý `(block, offset)` của phiên bản trong file heap |
| `cmin` / `cmax` | Số thứ tự câu lệnh trong transaction (dùng nội bộ) |
| `tableoid` | OID của bảng (hữu ích với partitioning / inheritance) |

```sql
SELECT xmin, xmax, ctid, id, name, price FROM products WHERE id = 10;
SELECT pg_current_xact_id();                    -- cấp một XID mới cho transaction hiện tại (autocommit: dùng 1 lần)
SELECT pg_current_snapshot();                   -- xmin:xmax:xip_list  (snapshot hiện tại)
SELECT pg_xact_commit_timestamp(xmin), * FROM products WHERE id = 10;   -- track_commit_timestamp = on
```

Ví dụ:

```text
 xmin | xmax |  ctid   | id |              name               | price
------+------+---------+----+---------------------------------+--------
  882 |    0 | (0,10)  | 10 | Sony Pro Headphones X42         |  89.99
```

`xmin = 882`: dòng được tạo bởi transaction 882 (data generator). `xmax = 0`: chưa ai xoá/sửa. `ctid = (0,10)`: block 0, line pointer 10.

## 2. UPDATE tạo phiên bản mới

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` | |
| t2 | `SELECT pg_current_xact_id();` → giả sử **91000** | |
| t3 | `SELECT xmin, xmax, ctid, price FROM products WHERE id = 10;` → `882 \| 0 \| (0,10) \| 89.99` | |
| t4 | `UPDATE products SET price = 79.99 WHERE id = 10;` | |
| t5 | `SELECT xmin, xmax, ctid, price FROM products WHERE id = 10;` → `91000 \| 0 \| (1690,5) \| 79.99` | |
| t6 | | `SELECT xmin, xmax, ctid, price FROM products WHERE id = 10;` → `882 \| 91000 \| (0,10) \| 89.99` |
| t7 | `COMMIT;` | |
| t8 | | `SELECT xmin, xmax, ctid, price FROM products WHERE id = 10;` → `91000 \| 0 \| (1690,5) \| 79.99` |

Giải thích:

- t4: PostgreSQL **không sửa** tuple ở `(0,10)`. Nó:
  1. ghi `xmax = 91000` vào header tuple cũ (đánh dấu "bị thay thế bởi transaction 91000"),
  2. chèn tuple mới với `xmin = 91000, xmax = 0` ở chỗ trống (ví dụ `(1690,5)` — trang khác vì trang 0 đã đầy),
  3. đặt `t_ctid` của tuple cũ trỏ tới `(1690,5)` (chuỗi phiên bản — *update chain*),
  4. thêm entry mới vào **mọi index** của bảng (vì tuple mới ở chỗ khác) — trừ khi là HOT (mục 4).
- t5: A thấy bản mới (của chính nó).
- t6: B thấy bản **cũ**: snapshot của B coi 91000 là "đang chạy" → bản mới (xmin=91000) vô hình, bản cũ (xmax=91000 chưa commit) vẫn hợp lệ. B thấy `xmax = 91000` — dấu vết của một transaction đang sửa dòng này. B không bị chặn khi đọc.
- t8: sau COMMIT, snapshot mới của B (READ COMMITTED) coi 91000 đã commit → thấy bản mới.

Thay vì COMMIT ở t7, thử `ROLLBACK`: tuple mới thành "rác" (xmin của transaction đã abort), tuple cũ có `xmax = 91000` nhưng 91000 abort nên xmax bị bỏ qua → dòng vẫn là bản cũ. **ROLLBACK trong PostgreSQL gần như tức thì** — không cần "hoàn tác" gì, chỉ ghi trạng thái aborted vào `pg_xact`.

### Quy tắc visibility (đơn giản hoá)

Một tuple **nhìn thấy được** với snapshot S nếu:

1. `xmin` đã commit **và** không nằm trong danh sách "đang chạy" của S (hoặc là transaction của chính mình), **và**
2. `xmax` = 0, **hoặc** `xmax` abort, **hoặc** `xmax` vẫn đang chạy/không thuộc về S, **hoặc** `xmax` chỉ là *row lock* (`FOR UPDATE`), không phải xoá.

Snapshot (`pg_current_snapshot()` → `xmin:xmax:xip_list`): mọi XID `< xmin` đã kết thúc; mọi XID `≥ xmax` là tương lai (vô hình); XID nằm trong `xip_list` là đang chạy (vô hình).

## 3. Nhìn tận mắt bằng `pageinspect`

Dùng bảng nháp `replication_test` (nhỏ, dễ xem block 0):

```sql
TRUNCATE replication_test;          -- bảng nháp, không ảnh hưởng dữ liệu lab
INSERT INTO replication_test (token, note) VALUES ('mvcc-1', 'a'), ('mvcc-2', 'b'), ('mvcc-3', 'c');

SELECT lp, lp_flags, t_xmin, t_xmax, t_ctid
FROM heap_page_items(get_raw_page('replication_test', 0));
```

```text
 lp | lp_flags | t_xmin | t_xmax | t_ctid
----+----------+--------+--------+--------
  1 |        1 |  91010 |      0 | (0,1)
  2 |        1 |  91010 |      0 | (0,2)
  3 |        1 |  91010 |      0 | (0,3)
```

```sql
UPDATE replication_test SET note = 'b2' WHERE token = 'mvcc-2';
DELETE FROM replication_test WHERE token = 'mvcc-3';

SELECT lp, lp_flags, t_xmin, t_xmax, t_ctid,
       CASE WHEN t_infomask & 2048 > 0 THEN 'xmax committed'  -- HEAP_XMAX_COMMITTED (hint bit)
            WHEN t_infomask & 1024 > 0 THEN 'xmin committed'  -- HEAP_XMIN_COMMITTED
       END AS hint
FROM heap_page_items(get_raw_page('replication_test', 0));
```

```text
 lp | lp_flags | t_xmin | t_xmax | t_ctid
----+----------+--------+--------+--------
  1 |        1 |  91010 |      0 | (0,1)     <- mvcc-1, còn sống
  2 |        1 |  91010 |  91011 | (0,4)     <- mvcc-2 bản CŨ: bị UPDATE bởi 91011, trỏ tới (0,4)
  3 |        1 |  91010 |  91012 | (0,3)     <- mvcc-3: bị DELETE bởi 91012 (ctid trỏ chính nó)
  4 |        1 |  91011 |      0 | (0,4)     <- mvcc-2 bản MỚI
```

Bảng chỉ có 2 dòng "sống", nhưng page chứa 4 tuple. `SELECT count(*) FROM replication_test;` → 2.

`lp_flags`: `0` UNUSED, `1` NORMAL, `2` REDIRECT, `3` DEAD.

**Hint bits**: lần đầu một tuple được đọc sau khi transaction tạo nó kết thúc, PostgreSQL tra `pg_xact` rồi ghi cờ "xmin committed" vào header — các lần đọc sau khỏi phải tra. Vì vậy một `SELECT` có thể làm page *dirty* (và với `wal_log_hints = on` còn sinh WAL!).

Sau `VACUUM replication_test;` xem lại: tuple 2 và 3 biến thành `lp_flags = 0` (UNUSED) hoặc DEAD/REDIRECT; chỗ trống được tái sử dụng cho INSERT sau.

## 4. HOT update (Heap-Only Tuple)

UPDATE thường phải chèn entry mới vào **mọi** index. Nếu:

1. không cột nào **được index** bị thay đổi, **và**
2. trang hiện tại **còn chỗ** cho phiên bản mới,

thì PostgreSQL đặt phiên bản mới **cùng trang** và **không** đụng tới index: index vẫn trỏ tới tuple cũ, tuple cũ có cờ *HOT_UPDATED* và chuỗi `t_ctid` dẫn tới bản mới.

```sql
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'products';

UPDATE products SET description = description || '' WHERE id = 20;   -- description không có index -> HOT (nếu trang còn chỗ)
UPDATE products SET price = price + 0.01 WHERE id = 21;               -- price có idx_products_price và ĐỔI giá trị -> KHÔNG HOT

SELECT pg_sleep(1);   -- thống kê được gửi bất đồng bộ
SELECT n_tup_upd, n_tup_hot_upd FROM pg_stat_user_tables WHERE relname = 'products';
```

> PostgreSQL so sánh giá trị cũ/mới của các cột được index: `SET price = price` (không đổi giá trị) vẫn có thể HOT; chỉ khi giá trị cột có index **thật sự đổi** thì mới phải cập nhật index.

Bảng mới nạp bằng COPY gần như đầy 100% mỗi trang → UPDATE đầu tiên thường **không** HOT được vì thiếu chỗ. Đó là lý do `fillfactor`:

```sql
ALTER TABLE inventory SET (fillfactor = 80);   -- chừa 20% mỗi trang cho bản cập nhật (áp dụng cho trang ghi mới / sau VACUUM FULL)
```

Bảng hay UPDATE (inventory, counters) hưởng lợi lớn: ít ghi index, ít WAL, ít bloat index.

## 5. Dead tuple, bloat và VACUUM

```sql
SELECT pg_size_pretty(pg_table_size('order_items')) AS size,
       n_live_tup, n_dead_tup, last_autovacuum
FROM pg_stat_user_tables WHERE relname = 'order_items';

-- tạo 300k dead tuples (giá trị không đổi nhưng vẫn là phiên bản mới)
UPDATE order_items SET discount = discount WHERE id <= 300000;

SELECT pg_size_pretty(pg_table_size('order_items')) AS size,
       n_live_tup, n_dead_tup
FROM pg_stat_user_tables WHERE relname = 'order_items';      -- size tăng, n_dead_tup ~ 300k

SELECT tuple_count, dead_tuple_count, round(dead_tuple_percent::numeric, 1) AS dead_pct,
       round(free_percent::numeric, 1) AS free_pct
FROM pgstattuple('order_items');
```

| Lệnh | Làm gì | Khoá | Trả dung lượng cho OS? |
| --- | --- | --- | --- |
| `VACUUM` | dọn dead tuple, ghi nhận chỗ trống vào FSM, cập nhật visibility map, freeze | `ShareUpdateExclusive` (đọc/ghi vẫn chạy) | chỉ phần cuối file nếu trống |
| `VACUUM FULL` | viết lại toàn bộ bảng + index | `AccessExclusive` (chặn **mọi thứ**) | có |
| autovacuum | `VACUUM`/`ANALYZE` tự động khi `n_dead_tup > 50 + 20% * reltuples` (mặc định) | như VACUUM, tự nhường khi bị xung đột | — |

```sql
VACUUM (VERBOSE, ANALYZE) order_items;
SELECT pg_size_pretty(pg_table_size('order_items')), n_dead_tup FROM pg_stat_user_tables WHERE relname = 'order_items';
-- size KHÔNG giảm (chỗ trống được tái sử dụng), n_dead_tup = 0
```

Dead tuple **không được dọn** nếu còn transaction nào có thể cần thấy nó. Thí nghiệm "VACUUM bị giữ chân":

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM warehouses;` *(giữ snapshot)* | |
| t2 | | `UPDATE order_items SET discount = discount WHERE id <= 100000;` |
| t3 | | `VACUUM (VERBOSE) order_items;` → `... 100000 are dead but not yet removable, oldest xmin: ...` |
| t4 | `COMMIT;` | |
| t5 | | `VACUUM (VERBOSE) order_items;` → dọn được |

Snapshot của A (kể cả trên bảng khác!) giữ *xmin horizon* của cả cluster. Đây là lý do một transaction "idle in transaction" vài giờ có thể làm mọi bảng phình to. Tìm thủ phạm: [sql/monitoring/activity.sql](../sql/monitoring/activity.sql) (mục "oldest snapshot holding back VACUUM"). Với `hot_standby_feedback = on`, query dài trên **replica** cũng giữ horizon này (xem `pg_replication_slots.xmin`).

## 6. Visibility map và Index Only Scan

Index **không** lưu `xmin/xmax`. Index Only Scan chỉ bỏ qua heap được với những page được đánh dấu **all-visible** trong visibility map (file `_vm`), và chỉ VACUUM mới đặt cờ này.

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders WHERE created_at >= now() - interval '90 days';
-- Index Only Scan ... Heap Fetches: 0

UPDATE orders SET updated_at = updated_at WHERE created_at >= now() - interval '90 days';

EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders WHERE created_at >= now() - interval '90 days';
-- Heap Fetches: ~N (mỗi dòng phải ghé heap kiểm tra visibility), Buffers tăng mạnh

VACUUM orders;
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders WHERE created_at >= now() - interval '90 days';
-- Heap Fetches: 0

CREATE EXTENSION IF NOT EXISTS pg_visibility;
SELECT * FROM pg_visibility_map_summary('orders');   -- số page all_visible / all_frozen
```

## 7. Transaction ID và wraparound

XID là số 32-bit (~4.2 tỷ), so sánh theo kiểu vòng tròn: với mỗi XID, ~2 tỷ XID "trong quá khứ" và ~2 tỷ "trong tương lai". Một tuple quá cũ mà chưa được đánh dấu **frozen** sẽ đột nhiên trông như "ở tương lai" → biến mất. VACUUM **freeze** tuple cũ (cờ `HEAP_XMIN_FROZEN`) để chúng luôn hiển thị.

```sql
SELECT datname, age(datfrozenxid) FROM pg_database ORDER BY 2 DESC;
SELECT relname, age(relfrozenxid) AS xid_age, pg_size_pretty(pg_table_size(oid))
FROM pg_class WHERE relkind = 'r' AND relnamespace = 'public'::regnamespace ORDER BY 2 DESC;
SHOW autovacuum_freeze_max_age;   -- 200,000,000: vượt mức này autovacuum ép VACUUM chống wraparound
```

`pg_current_xact_id()` trả `xid8` (64-bit, kèm "epoch") nên không quay vòng ở tầng SQL — nhưng tuple header vẫn lưu 32-bit.

## 8. MVCC trên replica

Replica nhận **chính các tuple header** (xmin/xmax/ctid y hệt) qua WAL. Thử:

```sql
-- PRIMARY và REPLICA, cùng câu:
SELECT xmin, xmax, ctid, id FROM products WHERE id = 10;   -- giống hệt nhau
```

Replica không cấp XID; snapshot trên replica được dựng từ danh sách transaction đang chạy mà primary ghi định kỳ vào WAL (record `Standby RUNNING_XACTS`, thấy trong [replication.md §4](replication.md#tự-quan-sát)).

## 9. Bài tập

1. Giải thích vì sao `SELECT count(*) FROM orders` phải đọc cả bảng (hoặc cả một index) thay vì đọc một "bộ đếm".
2. Mở transaction REPEATABLE READ ở session A, xoá 1000 dòng `replication_test` ở session B (đã chèn trước bằng `generate_series`), so sánh `count(*)` ở A và B, rồi xem `heap_page_items`.
3. Đo `n_tup_hot_upd` trước/sau khi `ALTER TABLE inventory SET (fillfactor = 70); VACUUM FULL inventory;` và cập nhật `quantity` 10,000 dòng (inventory không có index trên `quantity`).
4. Tại sao `UPDATE big_table SET col = col` (không đổi gì) vẫn tốn WAL, I/O và tạo dead tuple? Cách tránh: `WHERE col IS DISTINCT FROM new_value`.
5. Dọn dẹp: `TRUNCATE replication_test;` và (nếu đã đổi) `ALTER TABLE inventory RESET (fillfactor);`.
