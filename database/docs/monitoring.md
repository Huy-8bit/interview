# Monitoring — session, lock, kích thước, truy vấn chậm, replication

PostgreSQL tự thu thập rất nhiều thống kê trong các view `pg_stat_*`. Bài này hướng dẫn **đọc** chúng; các truy vấn đầy đủ nằm sẵn trong [sql/monitoring/](../sql/monitoring/) — mở bằng DBeaver (*File → Open File*) và chạy **từng câu** (Ctrl+Enter):

| File | Nội dung | Chạy trên |
| --- | --- | --- |
| [activity.sql](../sql/monitoring/activity.sql) | connection, query đang chạy, transaction dài, idle in transaction, xmin horizon, cancel/kill | primary (cũng chạy được trên replica) |
| [locks.sql](../sql/monitoring/locks.sql) | ai bị chặn, ai chặn, cây blocking, lock trên bảng nào, row lock (`pgrowlocks`) | primary |
| [size.sql](../sql/monitoring/size.sql) | kích thước DB/bảng/index, count chính xác vs ước lượng, index không dùng, seq scan vs index scan, cache hit, bloat, lịch sử autovacuum | primary |
| [performance.sql](../sql/monitoring/performance.sql) | `pg_stat_statements`, WAL, checkpoint, temp file, tham số khác mặc định, `pg_buffercache` | primary |
| [replication.sql](../sql/monitoring/replication.sql) | từng câu có nhãn `[PRIMARY]` / `[REPLICA]` — chạy nhầm node sẽ **cố ý** báo lỗi | cả hai |

Từ terminal (không cần cài psql trên máy):

```bash
./scripts/psql.sh primary -f /dev/stdin < sql/monitoring/size.sql
./scripts/check-replication.sh
```

Nguyên tắc chung khi đọc `pg_stat_*`:

- Phần lớn là **bộ đếm cộng dồn** kể từ lần reset cuối (`stats_reset`). Muốn đo một thí nghiệm: ghi lại giá trị trước, chạy, lấy hiệu số — hoặc reset (`SELECT pg_stat_reset();`, `SELECT pg_stat_statements_reset();`).
- Thống kê là **của từng node**. Query chạy trên replica không xuất hiện trong `pg_stat_statements`/`pg_stat_user_tables` của primary và ngược lại.
- `pg_stat_activity` là **ảnh chụp tức thời**; lock wait ngắn có thể không bao giờ bắt được — dùng log (`log_lock_waits = on`, đã bật trong lab).

---

## 1. Session: ai đang kết nối, đang làm gì

```sql
SELECT pid, usename, application_name, client_addr, state,
       wait_event_type, wait_event,
       now() - xact_start  AS xact_age,
       now() - query_start AS query_age,
       backend_xid, backend_xmin,
       left(query, 80)     AS query
FROM pg_stat_activity
WHERE backend_type = 'client backend' AND pid <> pg_backend_pid()
ORDER BY xact_start NULLS LAST;
```

| Cột | Ý nghĩa |
| --- | --- |
| `state` | `active` (đang chạy), `idle` (chờ lệnh, không trong transaction), `idle in transaction` (đã `BEGIN`, đang không chạy gì — **giữ lock và snapshot**), `idle in transaction (aborted)` (lỗi, chờ `ROLLBACK`) |
| `wait_event_type` / `wait_event` | đang chờ gì: `Lock/relation`, `Lock/transactionid` (row lock), `IO/DataFileRead`, `Client/ClientRead` (chờ client gửi lệnh), `LWLock/...` (nội bộ), NULL = đang dùng CPU |
| `xact_start` / `query_start` | transaction / câu lệnh hiện tại bắt đầu lúc nào |
| `backend_xid` | session đã ghi dữ liệu (có XID) |
| `backend_xmin` | snapshot đang giữ — chặn VACUUM dọn dead tuple (xem [transaction-lab.md §8.2](transaction-lab.md#82-giữ-snapshot-vacuum-không-dọn-được-dead-tuple)) |
| `application_name` | đặt trong DBeaver: *Connection → Edit → Driver properties → ApplicationName*. Replica xuất hiện là `pglab-replica`, generator là `data-generator` |

Xem cả các process nền (checkpointer, walwriter, walsender, autovacuum…):

```sql
SELECT pid, backend_type, state, wait_event FROM pg_stat_activity ORDER BY backend_type;
```

```bash
docker compose exec postgres-primary ps -o pid,cmd -u postgres     # cùng các process đó ở mức OS
```

Xử lý session có vấn đề:

```sql
SELECT pg_cancel_backend(12345);      -- huỷ câu lệnh đang chạy, giữ connection
SELECT pg_terminate_backend(12345);   -- đóng connection, rollback transaction của nó
```

**Thực hành**: mở 2 DBeaver session, làm kịch bản *idle in transaction* ở [transaction-lab.md §9](transaction-lab.md#9-idle-in-transaction), rồi tìm session đó bằng các query trong `activity.sql`.

---

## 2. Lock và blocking

Khi "database bị treo", câu hỏi đầu tiên luôn là: *ai đang chặn ai?*

```sql
SELECT blocked.pid                 AS blocked_pid,
       now() - blocked.query_start AS blocked_for,
       left(blocked.query, 60)     AS blocked_query,
       blocking.pid                AS blocking_pid,
       blocking.state              AS blocking_state,        -- thường là 'idle in transaction'
       now() - blocking.xact_start AS blocking_xact_age,
       left(blocking.query, 60)    AS blocking_last_query
FROM pg_stat_activity AS blocked
JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS b(pid) ON true
JOIN pg_stat_activity AS blocking ON blocking.pid = b.pid
ORDER BY blocked_for DESC;
```

`blocking_last_query` là **câu lệnh cuối cùng** session đó chạy, không nhất thiết là câu lấy lock (lock có thể đã được lấy từ nhiều câu trước trong cùng transaction).

Khi có hàng đợi nhiều tầng (A chặn B, B chặn C…), dùng truy vấn **blocking tree** (mục 2 trong `locks.sql`) để tìm **root blocker** — giết root blocker giải phóng cả cây. Ví dụ điển hình đo trên lab: một `ALTER TABLE` chờ một transaction đọc, và mọi `SELECT` sau đó xếp hàng sau `ALTER TABLE` ([transaction-lab.md §8.1](transaction-lab.md#81-hàng-đợi-lock-một-select-bình-thường-cũng-bị-treo)).

Chi tiết lock:

```sql
SELECT l.pid, l.locktype, l.relation::regclass, l.transactionid, l.mode, l.granted,
       a.state, left(a.query, 50) AS query
FROM pg_locks l JOIN pg_stat_activity a USING (pid)
WHERE a.datname = current_database() AND l.pid <> pg_backend_pid()
ORDER BY l.granted, l.pid;
```

- `granted = false` = đang chờ.
- `locktype = transactionid` + `mode = ShareLock` chưa được cấp = đang chờ **row lock** (chờ transaction đang giữ dòng kết thúc).
- `locktype = relation` + `AccessExclusiveLock` = DDL (`ALTER`, `DROP`, `TRUNCATE`, `VACUUM FULL`) — chặn mọi thứ trên bảng, kể cả `SELECT`.

Thống kê lịch sử:

```sql
SELECT deadlocks, conflicts FROM pg_stat_database WHERE datname = current_database();
```

```bash
docker compose logs postgres-primary | grep -E "still waiting|acquired|deadlock detected"   # log_lock_waits
```

---

## 3. Kích thước và sức khoẻ bảng

```sql
SELECT relname,
       pg_size_pretty(pg_total_relation_size(relid)) AS total,
       pg_size_pretty(pg_relation_size(relid))       AS heap,
       pg_size_pretty(pg_indexes_size(relid))        AS indexes,
       n_live_tup, n_dead_tup,
       last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

Trên lab ngay sau khi sinh dữ liệu:

```text
   relname   | total  |  heap  | indexes | n_live_tup
-------------+--------+--------+---------+------------
 orders      | 242 MB | 156 MB | 86 MB   |     500000
 order_items | 226 MB | 111 MB | 115 MB  |    1499494
 payments    | 120 MB | 80 MB  | 40 MB   |     512869
 reviews     | 72 MB  | 49 MB  | 22 MB   |     300000
 products    | 56 MB  | 39 MB  | 17 MB   |     100000
 users       | 52 MB  | 39 MB  | 13 MB   |     100000
```

Để ý `order_items`: index (115 MB) **lớn hơn** dữ liệu (111 MB) — 4 B-tree trên một bảng hẹp, trong đó một cái thừa ([index-lab.md §9](index-lab.md#9-index-thừa-và-index-không-dùng)).

Những thứ cần theo dõi:

| Dấu hiệu | Truy vấn (trong `size.sql`) | Ý nghĩa |
| --- | --- | --- |
| `seq_scan` cao, `seq_tup_read` khổng lồ trên bảng lớn | *Sequential vs index scans per table* | có thể thiếu index |
| `idx_scan = 0` trên index lớn, không phải constraint | *Unused indexes* | tốn dung lượng + chậm ghi |
| `n_dead_tup` cao, `last_autovacuum` lâu rồi | *Autovacuum / analyze history* | bloat; có thể bị transaction dài chặn |
| cache hit < 99% (OLTP) | *Cache hit ratio* | working set lớn hơn `shared_buffers` + OS cache |

`count(*)` chính xác phải quét toàn bộ bảng hoặc index; khi chỉ cần con số gần đúng dùng ước lượng của planner:

```sql
SELECT reltuples::bigint AS estimated_rows FROM pg_class WHERE oid = 'order_items'::regclass;
```

---

## 4. Truy vấn tốn tài nguyên nhất (`pg_stat_statements`)

Extension đã được nạp (`shared_preload_libraries`) và tạo sẵn. Nó gom các câu lệnh **cùng dạng** (literal thay bằng `$1`, `$2`) và cộng dồn số liệu:

```sql
SELECT calls,
       round(total_exec_time::numeric, 1)  AS total_ms,
       round(mean_exec_time::numeric, 2)   AS mean_ms,
       rows,
       round(100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS hit_pct,
       temp_blks_written,
       left(regexp_replace(query, '\s+', ' ', 'g'), 80) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Ngay sau khi generator chạy xong, top là các lệnh `COPY` của nó:

```text
 calls | total_ms | mean_ms |  rows   | hit_pct |                       query
-------+----------+---------+---------+---------+----------------------------------------------------
    50 |  19355.3 |  387.11 | 1499494 |   100.0 | COPY "order_items" ("order_id", "product_id", ...
    50 |   5844.0 |  116.88 |  500000 |   100.0 | COPY "orders" ("id", "user_id", "order_number", ...
```

Sắp xếp theo tiêu chí khác cho câu trả lời khác:

| ORDER BY | Trả lời câu hỏi |
| --- | --- |
| `total_exec_time` | query nào ngốn nhiều thời gian server nhất **tổng cộng** (tối ưu cái này lợi nhất) |
| `mean_exec_time` (với `calls >= 5`) | query nào chậm nhất **mỗi lần** (người dùng cảm nhận) |
| `calls` | query nào chạy nhiều nhất (ứng viên cache ở tầng app, N+1) |
| `shared_blks_read` | query nào đọc đĩa nhiều nhất |
| `temp_blks_written` | query nào sort/hash tràn ra đĩa (`work_mem`) |
| `wal_bytes` | query nào sinh nhiều WAL nhất (ảnh hưởng replication) |

**Thực hành**:

```sql
SELECT pg_stat_statements_reset();
```

Chạy vài bài trong [query-optimization-lab.md](query-optimization-lab.md) (cả bản chậm và bản đã tối ưu), rồi chạy lại truy vấn top 10. Các biến thể cùng dạng có bị gộp làm một không? `queryid` dùng để làm gì? (Gợi ý: `compute_query_id = on` → cùng `queryid` xuất hiện trong `pg_stat_activity.query_id` và trong log.)

---

## 5. WAL, checkpoint, temp file

```sql
-- WAL sinh ra kể từ lần reset
SELECT wal_records, wal_fpi, pg_size_pretty(wal_bytes) AS wal, stats_reset FROM pg_stat_wal;

-- Đo WAL của một câu lệnh
SELECT pg_current_wal_lsn() AS before \gset
UPDATE products SET updated_at = now() WHERE id <= 10000;
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), :'before')) AS wal_generated;   -- ~11 MB cho 10,000 dòng
-- (\gset là lệnh psql; trong DBeaver: ghi lại LSN bằng tay rồi dùng pg_wal_lsn_diff('0/...', '0/...'))

-- Checkpoint: "requested" nhiều hơn "timed" = max_wal_size quá nhỏ cho workload
SELECT checkpoints_timed, checkpoints_req, buffers_checkpoint, buffers_backend FROM pg_stat_bgwriter;

-- Temp file (sort/hash vượt work_mem)
SELECT temp_files, pg_size_pretty(temp_bytes) FROM pg_stat_database WHERE datname = current_database();
```

Câu hỏi: `wal_fpi` (full page image) tăng mạnh ngay sau mỗi checkpoint. Vì sao? (Lần sửa đầu tiên của mỗi trang sau checkpoint phải ghi **cả trang** vào WAL để chống *torn page*.) Thử `CHECKPOINT;` rồi đo lại WAL của cùng câu `UPDATE`.

Log của server (lab bật `log_checkpoints`, `log_temp_files = 10MB`, `log_min_duration_statement = 1s`, `log_autovacuum_min_duration = 10s`):

```bash
docker compose logs --since 10m postgres-primary | grep -E "checkpoint (starting|complete)|temporary file|duration:|automatic vacuum"
```

---

## 6. Replication

Script tổng hợp: `./scripts/check-replication.sh`. Các metric chính:

```sql
-- PRIMARY: mỗi standby một dòng
SELECT application_name, client_addr, state, sync_state,
       pg_current_wal_lsn() AS current_lsn, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag_bytes,
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication;

-- PRIMARY: slot giữ bao nhiêu WAL
SELECT slot_name, active, wal_status, xmin,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;

-- REPLICA
SELECT pg_is_in_recovery(), pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();
SELECT status, sender_host, slot_name, last_msg_receipt_time FROM pg_stat_wal_receiver;
SELECT * FROM pg_stat_database_conflicts WHERE datname = current_database();
```

Hai cái bẫy khi đọc lag:

- `write_lag` / `flush_lag` / `replay_lag` là **NULL** khi primary không có gì mới để gửi — không phải lỗi, mà là "không có lag để đo".
- `now() - pg_last_xact_replay_timestamp()` trên replica **không phải lag**: trên hệ thống không có ghi, con số này tăng mãi dù replica đã bắt kịp. Lag đúng = khoảng cách LSN giữa `pg_current_wal_lsn()` của primary và `pg_last_wal_replay_lsn()` của replica (script `check-replication.sh` tính đúng cách này).

Giải thích từng metric, thí nghiệm tạo lag và failover: [replication.md](replication.md#5-giám-sát-lsn-lag-và-từng-metric).

---

## 7. Checklist khi "database chậm"

1. `pg_stat_activity`: bao nhiêu session `active`? Đang chờ gì (`wait_event_type`)? Có ai `idle in transaction` lâu?
2. Có blocking không? (`pg_blocking_pids`, blocking tree)
3. Query nào đang ngốn tài nguyên? (`pg_stat_statements` sau khi reset 5–10 phút)
4. Có sort/hash tràn đĩa không? (`temp_files`, `temp_blks_written`)
5. Autovacuum có theo kịp không? (`n_dead_tup`, `last_autovacuum`, transaction dài giữ `xmin`)
6. Checkpoint có quá dày không? (`checkpoints_req`)
7. Replica có tụt lại không, slot có giữ quá nhiều WAL không? (`pg_stat_replication`, `pg_replication_slots`)
8. Với query cụ thể: `EXPLAIN (ANALYZE, BUFFERS)` → [query-optimization-lab.md](query-optimization-lab.md#8-một-quy-trình-tối-ưu).

---

## 8. Bài tập

1. Reset thống kê, rồi tạo tải bằng 2 session: Session A chạy 20 lần truy vấn "user theo số điện thoại" (Seq Scan, [index-lab.md §1](index-lab.md#1-b-tree-một-cột-tìm-user-theo-số-điện-thoại)); Session B chạy 20 lần truy vấn theo `id`. Dùng `pg_stat_statements` và `pg_stat_user_tables.seq_scan / seq_tup_read` để **chứng minh** bằng số liệu bảng nào cần index nào.
2. Tạo 1 triệu dead tuple: `UPDATE order_items SET discount = discount WHERE id <= 1000000;` (trong lúc đó Session B giữ một transaction `REPEATABLE READ` mở). Theo dõi `n_dead_tup`, kích thước bảng, và autovacuum trong `docker compose logs`. Đóng Session B và quan sát autovacuum dọn dẹp.
3. Chạy `./scripts/backup.sh --from-replica` trong khi Session A trên **primary** liên tục `UPDATE` một bảng lớn. `pg_stat_database_conflicts` trên replica có tăng không? Vì sao không (gợi ý: `hot_standby_feedback = on`)? Tắt nó **trên replica** (`ALTER SYSTEM` ghi vào `postgresql.auto.conf`, chạy được cả trên node read-only) và thử lại:

   ```sql
   -- REPLICA (5433)
   ALTER SYSTEM SET hot_standby_feedback = off;
   SELECT pg_reload_conf();      -- bất đồng bộ: SHOW ở session mới sau ~1s
   -- ... thí nghiệm ...
   ALTER SYSTEM RESET hot_standby_feedback;
   SELECT pg_reload_conf();
   ```
