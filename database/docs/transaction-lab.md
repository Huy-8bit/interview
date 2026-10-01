# Transaction Lab — 2 session, isolation level, lock, deadlock

## 0. Chuẩn bị

Mở **2 connection tới PRIMARY** (`localhost:5432`) — gọi là **Session A** và **Session B**. (Thêm Session C để giám sát.)

**DBeaver**:

- Tạo 2 SQL editor trên cùng connection, và bật *"Open separate connection for each editor"* (Preferences → Editors → SQL Editor → *Open separate connection for each editor*) — nếu không, 2 editor dùng chung một session và thí nghiệm vô nghĩa.
- Chuyển sang **Manual commit** (nút *Auto-commit* trên toolbar, hoặc `Ctrl+Alt+'`) — hoặc đơn giản là luôn gõ `BEGIN;` ở đầu mỗi kịch bản như bên dưới.
- Chạy **từng câu** (Ctrl+Enter), theo đúng thứ tự thời gian `t1, t2, ...`.

**psql**: mở 2 terminal, mỗi cái chạy `./scripts/psql.sh`.

Kiểm tra mình đang ở session nào và transaction nào:

```sql
SELECT pg_backend_pid() AS pid, pg_current_xact_id_if_assigned() AS xid, current_setting('transaction_isolation');
```

Dữ liệu dùng trong lab (chạy một lần, bất kỳ session nào, autocommit):

```sql
UPDATE inventory SET quantity = 100, reserved_quantity = 0 WHERE id IN (1, 2);
SELECT id, product_id, warehouse_id, quantity, reserved_quantity FROM inventory WHERE id IN (1, 2);
```

Session C — xem ai đang làm gì / chờ ai (chạy bất cứ lúc nào):

```sql
SELECT pid, state, pg_blocking_pids(pid) AS blocked_by, wait_event_type, wait_event,
       backend_xid, backend_xmin, left(query, 60) AS query
FROM pg_stat_activity
WHERE datname = 'ecommerce' AND backend_type = 'client backend' AND pid <> pg_backend_pid();
```

Isolation level trong PostgreSQL:

| Level | Snapshot | Dirty read | Non-repeatable read | Phantom read | Serialization anomaly |
| --- | --- | --- | --- | --- | --- |
| READ UNCOMMITTED | (= READ COMMITTED) | không | có | có | có |
| **READ COMMITTED** (mặc định) | mới cho **mỗi câu lệnh** | không | có | có | có |
| REPEATABLE READ | một snapshot cho **cả transaction** | không | không | **không** (chặt hơn chuẩn SQL) | có (write skew) |
| SERIALIZABLE | như RR + SSI theo dõi phụ thuộc | không | không | không | **không** |

---

## 1. Lost Update

Hai người cùng "đọc → tính trong ứng dụng → ghi lại". Kho có 100, A bán 3, B bán 2 → phải còn 95.

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` | |
| t2 | `SELECT quantity FROM inventory WHERE id = 1;` → **100** | |
| t3 | | `BEGIN;` |
| t4 | | `SELECT quantity FROM inventory WHERE id = 1;` → **100** |
| t5 | `UPDATE inventory SET quantity = 97 WHERE id = 1;` *(app tính 100 − 3)* | |
| t6 | | `UPDATE inventory SET quantity = 98 WHERE id = 1;` *(app tính 100 − 2)* → **bị treo** (chờ A) |
| t7 | `COMMIT;` | → B chạy tiếp: `UPDATE 1` |
| t8 | | `COMMIT;` |
| t9 | `SELECT quantity FROM inventory WHERE id = 1;` → **98** ❌ | |

Lần bán của A **biến mất**. PostgreSQL không sai: B đã ra lệnh "đặt thành 98" và UPDATE của B chỉ chờ lock dòng rồi ghi đè. Lỗi nằm ở pattern read-modify-write ngoài database.

**Sửa (a) — UPDATE nguyên tử**: để database tự tính trên giá trị mới nhất.

```sql
UPDATE inventory SET quantity = 100 WHERE id = 1;           -- reset
-- A:  BEGIN; UPDATE inventory SET quantity = quantity - 3 WHERE id = 1;
-- B:  BEGIN; UPDATE inventory SET quantity = quantity - 2 WHERE id = 1;   -- chờ A
-- A:  COMMIT;
-- B:  (chạy tiếp, đọc lại phiên bản MỚI của dòng = 97, tính 97 - 2)  COMMIT;
SELECT quantity FROM inventory WHERE id = 1;                -- 95 ✅
```

Ở READ COMMITTED, khi B được nhả lock, PostgreSQL **đánh giá lại** biểu thức và điều kiện `WHERE` trên phiên bản mới nhất của dòng (*EvalPlanQual*). Đó là lý do `quantity = quantity - 2` và `WHERE quantity >= 2` an toàn.

**Sửa (b) — Pessimistic lock `SELECT ... FOR UPDATE`**: lặp lại bảng trên nhưng t2 và t4 dùng `SELECT quantity FROM inventory WHERE id = 1 FOR UPDATE;`. B bị treo ngay ở t4, chỉ đọc được **97** sau khi A commit → app tính đúng 95.

**Sửa (c) — REPEATABLE READ**: lặp lại bảng trên với `BEGIN ISOLATION LEVEL REPEATABLE READ;`. Ở t7 B nhận:

```text
ERROR:  could not serialize access due to concurrent update
```

B phải `ROLLBACK` và **thử lại toàn bộ transaction** (đọc lại 97). Ứng dụng dùng RR/SERIALIZABLE bắt buộc phải có vòng retry cho SQLSTATE `40001`.

**Sửa (d) — Optimistic locking**: không khoá; khi ghi kiểm tra "không ai sửa kể từ lúc tôi đọc":

```sql
SELECT quantity, updated_at FROM inventory WHERE id = 1;          -- nhớ updated_at
UPDATE inventory SET quantity = 97
WHERE id = 1 AND updated_at = '<giá trị vừa đọc>';                -- UPDATE 0 => có người sửa trước, đọc lại & thử lại
```

(Trigger `trg_inventory_updated_at` tự đổi `updated_at` mỗi lần UPDATE — đóng vai trò "version". Hệ thống lớn thường dùng cột `version integer`.)

---

## 2. Dirty Read

Đọc dữ liệu **chưa commit** của transaction khác.

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` | |
| t2 | `UPDATE inventory SET quantity = 0 WHERE id = 1;` | |
| t3 | | `BEGIN ISOLATION LEVEL READ UNCOMMITTED;` |
| t4 | | `SELECT quantity FROM inventory WHERE id = 1;` → **100** (giá trị cũ) |
| t5 | `ROLLBACK;` | |
| t6 | | `COMMIT;` |

PostgreSQL **không bao giờ** cho dirty read, kể cả ở READ UNCOMMITTED (được xử lý như READ COMMITTED). Lý do nằm ở MVCC: phiên bản mới do A tạo có `xmin` = XID của A; snapshot của B coi XID đó là "đang chạy" nên phiên bản đó vô hình, B đọc phiên bản cũ. Và B **không bị chặn**: *reader không chặn writer, writer không chặn reader*. Xem [mvcc-lab.md](mvcc-lab.md).

---

## 3. Non-repeatable Read

Trong **một** transaction, đọc cùng một dòng hai lần ra hai giá trị khác nhau.

| t | Session A (READ COMMITTED) | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` | |
| t2 | `SELECT quantity FROM inventory WHERE id = 1;` → **100** | |
| t3 | | `UPDATE inventory SET quantity = 50 WHERE id = 1;` *(autocommit)* |
| t4 | `SELECT quantity FROM inventory WHERE id = 1;` → **50** ⚠️ | |
| t5 | `COMMIT;` | |

READ COMMITTED lấy **snapshot mới cho mỗi câu lệnh** → thấy mọi thứ đã commit trước khi câu lệnh bắt đầu.

Làm lại với `BEGIN ISOLATION LEVEL REPEATABLE READ;` ở t1 (nhớ reset `quantity = 100`): t4 vẫn trả **100** — snapshot được chụp ở **câu lệnh đầu tiên** của transaction (t2, không phải lúc `BEGIN`) và dùng cho tới cuối.

Câu hỏi: nếu ở REPEATABLE READ, sau t3 session A chạy `UPDATE inventory SET quantity = quantity - 1 WHERE id = 1;` thì sao? (→ lỗi serialization như 1(c), vì dòng đã bị sửa sau snapshot của A.)

---

## 4. Phantom Read

Chạy lại **cùng một điều kiện** và thấy **thêm/bớt dòng**.

```sql
-- reset: dùng bảng nháp replication_test
DELETE FROM replication_test WHERE token LIKE 'phantom-%';
```

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` *(READ COMMITTED)* | |
| t2 | `SELECT count(*) FROM replication_test WHERE token LIKE 'phantom-%';` → **0** | |
| t3 | | `INSERT INTO replication_test (token) VALUES ('phantom-1'), ('phantom-2');` |
| t4 | `SELECT count(*) FROM replication_test WHERE token LIKE 'phantom-%';` → **2** 👻 | |
| t5 | `COMMIT;` | |

Làm lại với `BEGIN ISOLATION LEVEL REPEATABLE READ;` (xoá `phantom-%` trước): t4 vẫn là **0**. Chuẩn SQL cho phép phantom ở REPEATABLE READ, nhưng PostgreSQL thì không — vì snapshot MVCC áp dụng cho **mọi** dòng, kể cả dòng mới chèn. (MySQL/InnoDB đạt điều tương tự bằng *gap lock*; PostgreSQL không cần gap lock.)

---

## 5. Row Lock: `SELECT ... FOR UPDATE`

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` | |
| t2 | `SELECT * FROM inventory WHERE id = 1 FOR UPDATE;` | |
| t3 | | `SELECT * FROM inventory WHERE id = 1;` → trả về ngay (đọc thường không bị chặn) |
| t4 | | `SELECT * FROM inventory WHERE id = 1 FOR UPDATE;` → **treo** |
| t5 | *(Session C chạy truy vấn giám sát ở mục 0: B có `blocked_by = {pid A}`, `wait_event = transactionid`)* | |
| t6 | `COMMIT;` | → B nhận dòng (phiên bản mới nhất) |
| t7 | | `COMMIT;` |

Quan sát lock ở t5 (Session C):

```sql
SELECT l.pid, l.locktype, l.relation::regclass, l.transactionid, l.mode, l.granted
FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid
WHERE a.datname = 'ecommerce' AND l.pid <> pg_backend_pid()
ORDER BY l.granted, l.pid;

SELECT * FROM pgrowlocks('inventory');   -- dòng nào đang bị khoá, bởi XID nào, mode nào
```

Bạn sẽ thấy B **chờ `ShareLock` trên `transactionid` của A** — không phải một lock "trên dòng". Row lock được ghi thẳng vào header tuple (`xmax` = XID của A + cờ lock). Nhờ vậy khoá một triệu dòng không tốn một triệu mục trong bảng lock; người chờ thì xếp hàng chờ **transaction** giữ khoá kết thúc.

Các mức row lock (mạnh → yếu):

| Lock | Lấy bởi | Xung đột với |
| --- | --- | --- |
| `FOR UPDATE` | `DELETE`, UPDATE cột khoá (PK/unique), `SELECT FOR UPDATE` | mọi mức |
| `FOR NO KEY UPDATE` | `UPDATE` thông thường | `FOR UPDATE`, `FOR NO KEY UPDATE`, `FOR SHARE` |
| `FOR SHARE` | `SELECT FOR SHARE` | `FOR UPDATE`, `FOR NO KEY UPDATE` |
| `FOR KEY SHARE` | kiểm tra **foreign key** khi chèn dòng con | chỉ `FOR UPDATE` |

Thí nghiệm FK:

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` | |
| t2 | `INSERT INTO reviews (product_id, user_id, rating) VALUES (1, 7, 5);` *(khoá product 1 `FOR KEY SHARE`)* | |
| t3 | | `UPDATE products SET price = price WHERE id = 1;` → **không bị chặn** (NO KEY UPDATE) |
| t4 | | `DELETE FROM products WHERE id = 1;` → **treo** (cần FOR UPDATE) |
| t5 | `ROLLBACK;` | → B chạy tiếp (DELETE thành công, hoặc lỗi FK nếu sản phẩm đã có order_items) |
| t6 | | `ROLLBACK;` ⚠️ đừng COMMIT |

Ở thí nghiệm này Session B cũng phải bắt đầu bằng `BEGIN;` (trước t3).

`SKIP LOCKED` và `NOWAIT`: xem [sql-solutions.md 9.2, 9.3](sql-solutions.md#92).

---

## 6. Isolation Level: READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE

### 6.1 Cùng UPDATE một dòng

```sql
UPDATE inventory SET quantity = 100 WHERE id = 1;   -- reset
```

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN ISOLATION LEVEL <X>;` | `BEGIN ISOLATION LEVEL <X>;` |
| t2 | `SELECT quantity FROM inventory WHERE id = 1;` | `SELECT quantity FROM inventory WHERE id = 1;` |
| t3 | `UPDATE inventory SET quantity = quantity - 10 WHERE id = 1;` | |
| t4 | | `UPDATE inventory SET quantity = quantity - 20 WHERE id = 1;` → treo |
| t5 | `COMMIT;` | |

| `<X>` | B sau t5 |
| --- | --- |
| READ COMMITTED | `UPDATE 1` → tính lại trên phiên bản mới: 90 − 20 = **70** |
| REPEATABLE READ | `ERROR: could not serialize access due to concurrent update` |
| SERIALIZABLE | `ERROR: could not serialize access due to concurrent update` |

### 6.2 Write skew: REPEATABLE READ cho lọt, SERIALIZABLE chặn

Quy tắc nghiệp vụ: **mỗi user phải còn ít nhất 1 địa chỉ**. User `1` có đúng 2 địa chỉ. Hai thiết bị cùng lúc xoá **hai địa chỉ khác nhau**, mỗi bên đều kiểm tra "còn ≥ 2 thì mới xoá".

```sql
SELECT id, user_id, city, is_default FROM addresses WHERE user_id = 1 ORDER BY id;   -- ghi lại 2 id: <a1>, <a2>
```

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | `BEGIN ISOLATION LEVEL REPEATABLE READ;` |
| t2 | `SELECT count(*) FROM addresses WHERE user_id = 1;` → 2 ✅ | |
| t3 | | `SELECT count(*) FROM addresses WHERE user_id = 1;` → 2 ✅ |
| t4 | `DELETE FROM addresses WHERE id = <a1>;` | |
| t5 | | `DELETE FROM addresses WHERE id = <a2>;` *(không bị chặn: dòng khác)* |
| t6 | `COMMIT;` | |
| t7 | | `COMMIT;` → **thành công** |
| t8 | `SELECT count(*) FROM addresses WHERE user_id = 1;` → **0** ❌ vi phạm quy tắc | |

Không có dòng nào bị cả hai cùng sửa → không có "concurrent update" → REPEATABLE READ không phát hiện. Đây là **write skew**: mỗi transaction đúng khi chạy một mình, nhưng chạy xen kẽ thì sai.

User 1 giờ đã mất cả 2 địa chỉ (đã COMMIT). Làm lại với `SERIALIZABLE` trên **một user khác** có đúng 2 địa chỉ:

```sql
SELECT user_id FROM addresses GROUP BY user_id HAVING count(*) = 2 ORDER BY user_id LIMIT 5;
```

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | `BEGIN ISOLATION LEVEL SERIALIZABLE;` |
| t2–t5 | *như trên* | *như trên* |
| t6 | `COMMIT;` → OK | |
| t7 | | `COMMIT;` → ❌ |

```text
ERROR:  could not serialize access due to read/write dependencies among transactions
DETAIL:  Reason code: Canceled on identification as a pivot, during commit attempt.
HINT:  The transaction might succeed if retried.
```

SERIALIZABLE (SSI — *Serializable Snapshot Isolation*) ghi lại mỗi transaction **đã đọc gì** (SIRead lock — xem `SELECT * FROM pg_locks WHERE mode = 'SIReadLock';`) và phát hiện vòng phụ thuộc đọc-ghi nguy hiểm. Không có lock chặn thêm, chỉ huỷ một bên → ứng dụng **phải retry**.

Cách khác để chặn write skew ở READ COMMITTED: khoá "tài nguyên chung" — ví dụ `SELECT ... FROM users WHERE id = 1 FOR UPDATE;` trước khi kiểm tra/xoá địa chỉ, để hai transaction phải xếp hàng.

---

## 7. Deadlock

| t | Session A | Session B |
| --- | --- | --- |
| t1 | `BEGIN;` | `BEGIN;` |
| t2 | `UPDATE inventory SET quantity = quantity - 1 WHERE id = 1;` | |
| t3 | | `UPDATE inventory SET quantity = quantity - 1 WHERE id = 2;` |
| t4 | `UPDATE inventory SET quantity = quantity - 1 WHERE id = 2;` → treo (chờ B) | |
| t5 | | `UPDATE inventory SET quantity = quantity - 1 WHERE id = 1;` → treo (chờ A) → **vòng tròn** |

Sau `deadlock_timeout` (1s) một process chạy *deadlock detector*, phát hiện chu trình và huỷ **một** transaction:

```text
ERROR:  deadlock detected
DETAIL:  Process 2345 waits for ShareLock on transaction 81234; blocked by process 2301.
Process 2301 waits for ShareLock on transaction 81235; blocked by process 2345.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,1) in relation "inventory"
```

Bên còn lại chạy tiếp; bên bị huỷ phải `ROLLBACK` (và retry). Log server có đầy đủ câu lệnh của hai bên:

```bash
docker compose logs postgres-primary | grep -A6 "deadlock detected"
```

```sql
SELECT deadlocks FROM pg_stat_database WHERE datname = 'ecommerce';
```

**Phòng tránh**:

1. Khoá theo **thứ tự nhất quán** (luôn theo `id` tăng dần): `SELECT ... WHERE id IN (1, 2) ORDER BY id FOR UPDATE;` trước khi UPDATE.
2. Transaction **ngắn**, không chờ người dùng / gọi API bên ngoài khi đang giữ lock.
3. Dùng `lock_timeout` để thất bại nhanh.

---

## 8. Long-running transaction

Một transaction "chạy lâu" (báo cáo nặng, batch job, hoặc đơn giản là ai đó mở `BEGIN` trong DBeaver rồi đi ăn trưa) gây hai loại thiệt hại khác nhau: **giữ lock** và **giữ snapshot**.

### 8.1 Hàng đợi lock: một SELECT bình thường cũng bị treo

Mọi câu lệnh đọc bảng đều lấy `AccessShareLock` trên bảng đó và giữ **tới hết transaction**. `ALTER TABLE` cần `AccessExclusiveLock` — xung đột với mọi thứ. Lock trong PostgreSQL xếp hàng **FIFO**: ai đến sau một yêu cầu đang chờ thì phải chờ sau nó, kể cả khi bản thân không xung đột với người đang giữ lock.

| t | Session A | Session B | Session C |
| --- | --- | --- | --- |
| t1 | `BEGIN;` | | |
| t2 | `SELECT count(*) FROM orders WHERE id < 10;` *(giữ AccessShareLock tới khi COMMIT)* | | |
| t3 | | `ALTER TABLE orders ADD COLUMN tmp_col int;` → **treo** | |
| t4 | | | `SELECT id FROM orders WHERE id = 1;` → **cũng treo** ❗ |
| t5 | *(Session D chạy truy vấn giám sát bên dưới)* | | |
| t6 | `COMMIT;` | → ALTER chạy xong | → SELECT trả kết quả |
| t7 | | `ALTER TABLE orders DROP COLUMN tmp_col;` | |

Giám sát ở t5:

```sql
SELECT pid, application_name, state, wait_event_type, wait_event,
       pg_blocking_pids(pid) AS blocked_by, left(query, 45) AS query
FROM pg_stat_activity
WHERE datname = 'ecommerce' AND backend_type = 'client backend' AND pid <> pg_backend_pid()
ORDER BY backend_start;

SELECT l.pid, a.application_name, l.mode, l.granted
FROM pg_locks l JOIN pg_stat_activity a USING (pid)
WHERE l.relation = 'orders'::regclass
ORDER BY l.granted DESC, l.pid;
```

Kết quả thật đo trên lab này (đặt `application_name` để dễ nhìn):

```text
 pid |    app    | state  | wait_event_type | wait_event | blocked_by |                   query
-----+-----------+--------+-----------------+------------+------------+--------------------------------------------
 634 | session_A | active | Timeout         | PgSleep    | {}         | SELECT pg_sleep(9);
 640 | session_B | active | Lock            | relation   | {634}      | ALTER TABLE orders ADD COLUMN tmp_col int;
 646 | session_C | active | Lock            | relation   | {640}      | SELECT id FROM orders WHERE id = 1;

 pid | application_name |        mode         | granted
-----+------------------+---------------------+---------
 634 | session_A        | AccessShareLock     | t
 640 | session_B        | AccessExclusiveLock | f
 646 | session_C        | AccessShareLock     | f
```

Điểm mấu chốt: C bị chặn bởi **B** (`blocked_by = {640}`), không phải A. Trên production, đây là cách một migration "chỉ thêm một cột" làm sập toàn bộ API: mọi request đọc bảng `orders` dồn sau câu `ALTER`, connection pool cạn.

**Phòng tránh**: luôn đặt `lock_timeout` cho DDL và retry:

```sql
SET lock_timeout = '3s';
ALTER TABLE orders ADD COLUMN tmp_col int;
-- ERROR:  canceling statement due to lock timeout   -> B tự huỷ, hàng đợi được giải phóng, thử lại sau
```

### 8.2 Giữ snapshot: VACUUM không dọn được dead tuple

Transaction ở `REPEATABLE READ` / `SERIALIZABLE` (hoặc **một câu lệnh** chạy lâu ở `READ COMMITTED`) giữ một snapshot — thể hiện ở cột `backend_xmin`. Mọi phiên bản dòng bị xoá/cập nhật **sau** `backend_xmin` đó có thể vẫn còn cần với snapshot này, nên VACUUM phải giữ lại — trên **mọi bảng** của database, không chỉ bảng mà transaction đang đọc.

| t | Session A | Session B |
| --- | --- | --- |
| t0 | | `INSERT INTO replication_test (token, note) SELECT 'vac-' \|\| g, 'vacuum lab' FROM generate_series(1, 10000) g;` |
| t1 | `BEGIN ISOLATION LEVEL REPEATABLE READ;` | |
| t2 | `SELECT count(*) FROM users WHERE id = 1;` *(snapshot được chụp ở câu lệnh đầu tiên)* | |
| t3 | | `DELETE FROM replication_test WHERE token LIKE 'vac-%';` |
| t4 | | `VACUUM (VERBOSE) replication_test;` |
| t5 | `COMMIT;` | |
| t6 | | `VACUUM (VERBOSE) replication_test;` |

Ở t4 (A vẫn mở — chú ý A **không hề đọc** `replication_test`):

```text
tuples: 0 removed, 10001 remain, 10000 are dead but not yet removable
removable cutoff: 936, which was 1 XIDs old when operation ended
```

Ở t6 (sau khi A commit):

```text
tuples: 10000 removed, 1 remain, 0 are dead but not yet removable
removable cutoff: 937, which was 1 XIDs old when operation ended
```

Tìm thủ phạm giữ `xmin` lâu nhất:

```sql
SELECT pid, application_name, state, backend_xmin, age(backend_xmin) AS xmin_age_xids,
       now() - xact_start AS xact_age, left(query, 60) AS query
FROM pg_stat_activity
WHERE backend_xmin IS NOT NULL
ORDER BY age(backend_xmin) DESC;

-- Cả replication slot cũng có thể giữ xmin: replica của lab bật hot_standby_feedback,
-- nên một query dài trên REPLICA (5433) cũng làm VACUUM trên PRIMARY không dọn được.
SELECT slot_name, xmin, catalog_xmin, age(xmin) AS xmin_age FROM pg_replication_slots;
```

Thử: mở `BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM orders;` trên **replica**, rồi lặp lại t3–t4 trên primary — VACUUM vẫn báo *dead but not yet removable*; `pg_replication_slots.xmin` chính là `backend_xmin` của transaction trên replica.

Hậu quả nếu để lâu: bảng/index phình (bloat), Index Only Scan phải đọc heap nhiều hơn (visibility map không được set), và ở mức cực đoan là nguy cơ **transaction ID wraparound** (xem [mvcc-lab.md](mvcc-lab.md#7-transaction-id-và-wraparound)).

**Phòng tránh**: transaction ngắn; báo cáo nặng chạy trên replica với `hot_standby_feedback` cân nhắc kỹ; giới hạn bằng `statement_timeout`, `idle_in_transaction_session_timeout`, và (PG17+) `transaction_timeout`; giám sát `max(age(backend_xmin))`.

Dọn dẹp: `DELETE FROM replication_test WHERE token LIKE 'vac-%'; VACUUM replication_test;`

---

## 9. Idle in transaction

| t | Session A | Session C |
| --- | --- | --- |
| t1 | `BEGIN; UPDATE inventory SET quantity = quantity WHERE id = 1;` rồi **không làm gì nữa** | |
| t2 | | chạy query "idle in transaction" trong [sql/monitoring/activity.sql](../sql/monitoring/activity.sql) |
| t3 | | `SELECT pg_terminate_backend(<pid A>);` |
| t4 | `SELECT 1;` → `FATAL: terminating connection due to administrator command` | |

Một transaction bỏ quên: giữ row lock (chặn người khác), giữ snapshot (`backend_xmin`) khiến VACUUM không dọn được dead tuple **trên toàn cluster** (và qua `hot_standby_feedback`, cả query dài trên replica cũng vậy). Phòng: `SET idle_in_transaction_session_timeout = '60s'` (theo role/database), và giám sát.

---

## 10. Tổng kết

| Hiện tượng | READ COMMITTED | REPEATABLE READ | SERIALIZABLE |
| --- | --- | --- | --- |
| Dirty read | ✅ không xảy ra | ✅ | ✅ |
| Non-repeatable read | ❌ xảy ra | ✅ | ✅ |
| Phantom read | ❌ xảy ra | ✅ (PostgreSQL) | ✅ |
| Lost update (read-modify-write) | ❌ xảy ra (cần FOR UPDATE / UPDATE nguyên tử) | ✅ báo lỗi 40001 | ✅ báo lỗi 40001 |
| Write skew | ❌ | ❌ | ✅ báo lỗi 40001 |
| Cần retry trong app | ít khi | có | có |

Dọn dẹp sau lab:

```sql
UPDATE inventory SET quantity = 100, reserved_quantity = 0 WHERE id IN (1, 2);
DELETE FROM replication_test WHERE token LIKE 'phantom-%';
```
