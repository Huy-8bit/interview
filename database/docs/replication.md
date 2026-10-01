# Streaming Replication — cấu hình, bên trong, giám sát, failover

Mục lục

1. [Tổng quan](#1-tổng-quan)
2. [Cấu hình](#2-cấu-hình)
3. [Bootstrap replica tự động](#3-bootstrap-replica-tự-động)
4. [Bên trong: một INSERT đi tới replica như thế nào](#4-bên-trong-một-insert-đi-tới-replica-như-thế-nào)
5. [Giám sát: LSN, lag và từng metric](#5-giám-sát-lsn-lag-và-từng-metric)
6. [Read / Write: primary vs replica](#6-read--write-primary-vs-replica)
7. [Xung đột truy vấn trên replica](#7-xung-đột-truy-vấn-trên-replica)
8. [Replication slot](#8-replication-slot)
9. [Synchronous replication](#9-synchronous-replication)
10. [Failover](#10-failover)
11. [Bài tập](#11-bài-tập)

---

## 1. Tổng quan

Lab dùng **physical streaming replication**:

- Replica là **bản sao từng byte** của toàn bộ cluster primary (mọi database, mọi bảng, index, sequence, role...). Không chọn được "chỉ replicate bảng X" — đó là việc của *logical replication*.
- Thứ được truyền đi là **WAL (Write-Ahead Log)** — nhật ký thay đổi ở mức *page vật lý* ("trong block 1234 của file 16758, chèn tuple này ở offset 5"), không phải câu SQL.
- Replica **replay** WAL giống hệt quy trình crash recovery, chỉ khác là nó không bao giờ "kết thúc recovery" (trừ khi bị promote), và cho phép SELECT trong lúc đó (**hot standby**).
- Hai node phải cùng **major version** và cùng kiến trúc CPU.
- Mặc định **asynchronous**: primary trả COMMIT cho client mà **không chờ** replica.

| | Physical streaming (lab này) | Logical replication |
| --- | --- | --- |
| Đơn vị | WAL record (page-level) | thay đổi dòng (INSERT/UPDATE/DELETE đã giải mã) |
| Phạm vi | toàn cluster | chọn bảng (publication) |
| Replica ghi được? | không | có (subscriber là DB bình thường) |
| Khác major version | không | có (dùng để nâng cấp) |
| DDL | được replicate | **không** |

## 2. Cấu hình

### Primary — [postgres/primary/postgresql.conf](../postgres/primary/postgresql.conf)

| Tham số | Giá trị | Ý nghĩa |
| --- | --- | --- |
| `wal_level` | `replica` | Mức thông tin ghi vào WAL. `minimal` không đủ để replica/PITR; `replica` đủ cho physical replication + archive; `logical` thêm thông tin để giải mã thành dòng. **Cần restart.** |
| `max_wal_senders` | `10` | Số process walsender tối đa = số replica + số `pg_basebackup` chạy đồng thời. `pg_basebackup --wal-method=stream` dùng **2** kết nối. |
| `max_replication_slots` | `10` | Số slot tối đa. |
| `wal_keep_size` | `512MB` | Luôn giữ lại ít nhất ngần này WAL cũ trong `pg_wal` — "lưới an toàn" cho replica **không dùng slot**. |
| `max_slot_wal_keep_size` | `4GB` | Giới hạn WAL mà **một slot** được phép giữ. Replica chết lâu → vượt ngưỡng → slot bị `lost`, primary không bị đầy đĩa (phải rebuild replica). Mặc định `-1` = vô hạn (nguy hiểm). |
| `wal_log_hints` | `on` | Ghi WAL cả khi chỉ thay đổi hint bits. Bắt buộc để dùng `pg_rewind` (đưa primary cũ quay lại làm replica sau failover). |
| `hot_standby` | `on` | Chỉ có tác dụng khi node là standby. Đặt sẵn để node này làm replica được sau failover. |
| `synchronous_standby_names` | `''` | Rỗng = async. Xem [mục 9](#9-synchronous-replication). |
| `track_commit_timestamp` | `on` | Lưu thời điểm commit từng transaction → `pg_xact_commit_timestamp(xmin)`. |

### Replica — [postgres/replica/postgresql.conf](../postgres/replica/postgresql.conf)

| Tham số | Giá trị | Ý nghĩa |
| --- | --- | --- |
| `hot_standby` | `on` | Cho phép kết nối và SELECT trong lúc đang recovery. `off` → replica từ chối mọi kết nối. |
| `hot_standby_feedback` | `on` | Walreceiver báo `xmin` của các query đang chạy trên replica về primary → VACUUM trên primary không xoá những dòng replica còn đang đọc → ít bị huỷ query. Đổi lại: bloat trên primary tăng nếu replica có query rất dài. |
| `max_standby_streaming_delay` | `30s` | Khi WAL cần replay xung đột với một query trên replica, replay được **chờ tối đa** ngần này rồi huỷ query. `-1` = chờ mãi (replica có thể trễ vô hạn). |
| `wal_receiver_status_interval` | `1s` | Tần suất replica gửi feedback (write/flush/replay LSN) → số liệu lag trên primary "tươi" hơn (mặc định 10s). |
| `recovery_min_apply_delay` | (tắt) | Bật lên (vd `5min`) để có **delayed replica** — lưới an toàn trước lệnh `DROP TABLE` nhầm. |
| `max_connections`, `max_wal_senders`, `max_worker_processes`, `max_locks_per_transaction`, `max_prepared_transactions` | = primary | Hot standby **bắt buộc** các giá trị này ≥ primary, nếu không replica từ chối khởi động. |
| `primary_conninfo`, `primary_slot_name` | trong `postgresql.auto.conf` | Do `pg_basebackup -R` ghi. |

### `pg_hba.conf`

```text
host    replication     all             samenet                 scram-sha-256
```

- `replication` là **pseudo-database**: khớp với kết nối kiểu *physical replication* (walreceiver, `pg_basebackup`). Một dòng `host all all ...` **không** cho phép replication.
- `all` user vẫn an toàn vì chỉ role có thuộc tính `REPLICATION` (hoặc superuser) mới mở được kết nối replication.
- `samenet` = mọi subnet mà server đang gắn vào → chính là Docker network của lab.

### Role `replicator`

Tạo trong [01-create-replication-user.sh](../postgres/primary/init/01-create-replication-user.sh):

```sql
CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD '...';
```

`REPLICATION` cho phép stream WAL / chạy `pg_basebackup`, nhưng **không** cho đọc bảng qua SQL:

```text
$ psql -U replicator -d ecommerce -c "SELECT count(*) FROM users"
ERROR:  permission denied for table users
```

Nguyên tắc *least privilege*: nếu mật khẩu replicator bị lộ, kẻ tấn công vẫn không `SELECT`/`DROP` được gì — dù vẫn có thể kéo toàn bộ data directory bằng `pg_basebackup`, nên vẫn phải bảo vệ nó.

## 3. Bootstrap replica tự động

[postgres/replica/entrypoint.sh](../postgres/replica/entrypoint.sh) chạy khi container replica start:

```text
volume chưa có .bootstrap-complete ?
 ├─ có  → bỏ qua, start postgres (tiếp tục stream từ LSN đã replay)
 └─ chưa:
      1. chờ pg_isready -h postgres-primary
      2. xoá pgdata dở dang (nếu lần trước bị ngắt)
      3. pg_basebackup --wal-method=stream --slot=replica_1_slot --write-recovery-conf --checkpoint=fast
      4. touch .bootstrap-complete
      5. exec postgres
```

| Cờ `pg_basebackup` | Tác dụng |
| --- | --- |
| `--wal-method=stream` | Mở **kết nối thứ hai** stream WAL phát sinh trong lúc copy. Bản copy data file là "fuzzy" (các trang được copy ở những thời điểm khác nhau); WAL này là thứ làm nó nhất quán. |
| `--slot=replica_1_slot` | Stream WAL qua slot → primary không xoá WAL mà replica chưa nhận, kể cả khoảng giữa "backup xong" và "replica start". |
| `--write-recovery-conf` (`-R`) | Tạo `standby.signal` và ghi `primary_conninfo` + `primary_slot_name` vào `postgresql.auto.conf`. |
| `--checkpoint=fast` | Yêu cầu primary checkpoint ngay (thay vì chờ checkpoint "spread") → backup bắt đầu tức thì. |

Log thực tế:

```text
[replica-entrypoint] running pg_basebackup (slot=replica_1_slot)
pg_basebackup: initiating base backup, waiting for checkpoint to complete
pg_basebackup: write-ahead log start point: 0/2000028 on timeline 1
pg_basebackup: base backup completed
LOG:  entering standby mode
LOG:  redo starts at 0/2000028
LOG:  consistent recovery state reached at 0/2000100
LOG:  database system is ready to accept read-only connections
LOG:  started streaming WAL from primary at 0/3000000 on timeline 1
```

`consistent recovery state reached` là thời điểm replica đã replay đủ WAL để dữ liệu nhất quán — **chỉ từ lúc này** nó mới nhận kết nối read-only.

## 4. Bên trong: một INSERT đi tới replica như thế nào

Ví dụ:

```sql
INSERT INTO replication_test (token) VALUES ('hello');   -- autocommit
```

```mermaid
sequenceDiagram
    autonumber
    participant C as Client
    participant B as Backend (primary)
    participant SB as Shared Buffers (primary)
    participant WB as WAL Buffers
    participant WF as pg_wal/ (primary)
    participant WS as walsender
    participant WR as walreceiver
    participant RW as pg_wal/ (replica)
    participant SU as startup process
    participant RB as Shared Buffers (replica)

    C->>B: INSERT ... (autocommit)
    B->>B: parse → plan → execute, cấp XID
    B->>SB: ghi tuple vào heap page (xmin = XID), page dirty
    B->>WB: XLogInsert: Heap INSERT record → LSN
    B->>SB: index pages + WAL Btree INSERT_LEAF
    B->>WB: COMMIT record
    B->>WF: XLogFlush: write() + fsync() tới hết COMMIT record
    B->>B: đánh dấu XID committed trong pg_xact (CLOG)
    B-->>C: COMMIT OK  (async: KHÔNG chờ replica)
    B-)WS: WalSndWakeup
    WS->>WF: đọc WAL từ vị trí đã gửi → flush LSN
    WS->>WR: TCP: XLogData(start LSN, data)
    WR->>RW: write() rồi fsync()
    WR-->>WS: feedback: write/flush/apply LSN
    SU->>RW: đọc record kế tiếp
    SU->>RB: redo: đọc page, so page LSN, áp thay đổi
    SU->>SU: COMMIT record → XID committed → dòng hiện ra cho query trên replica
```

### Bước 1 — Backend nhận câu lệnh

Mỗi kết nối có một **backend process** riêng. Backend parse, phân tích, lập kế hoạch rồi thực thi INSERT. Lần sửa đổi đầu tiên trong transaction khiến backend được cấp một **transaction ID (XID)** 32-bit (đọc bằng `txid_current()` / `pg_current_xact_id()`). Chỉ primary cấp được XID — đây là lý do căn bản vì sao replica không thể ghi.

### Bước 2 — Shared Buffers: sửa page trong bộ nhớ

Dữ liệu bảng lưu thành các **page 8KB**. Backend:

1. Hỏi **Free Space Map** trang nào còn chỗ.
2. Nạp trang đó vào **shared_buffers** (nếu chưa có), *pin* và khoá độc quyền buffer.
3. Ghi tuple mới vào page: header chứa `xmin = XID`, `xmax = 0`, line pointer mới → vị trí `ctid = (block, offset)`.
4. Đánh dấu page **dirty**.

Page **chưa** được ghi xuống file dữ liệu. Nếu server sập ngay lúc này, thay đổi sẽ được khôi phục từ WAL — nên việc ghi file dữ liệu có thể trì hoãn để gom nhiều thay đổi (hiệu năng).

### Bước 3 — WAL Record

Ngay trong lúc giữ khoá buffer, backend gọi `XLogInsert()` tạo **WAL record** mô tả thay đổi vật lý:

- *resource manager* (`Heap`), loại record (`INSERT`)
- tham chiếu block: `rel 1663/16384/16867 blk 0` = tablespace / database OID / relfilenode, số block
- dữ liệu tuple
- **Full Page Image (FPI)** nếu đây là lần sửa page *đầu tiên kể từ checkpoint gần nhất* (`full_page_writes = on`) — chống "torn page" khi OS chỉ ghi được một nửa trang 8KB lúc mất điện.

Record được gán **LSN** (Log Sequence Number) — vị trí byte trong dòng WAL, viết dạng `1/35648508`. **Page LSN** của trang được cập nhật = LSN cuối record. Luật *WAL-before-data*: một dirty page không bao giờ được ghi xuống đĩa trước khi WAL tới page LSN của nó đã được flush.

Index cũng là page, nên mỗi index của bảng sinh thêm một record (`Btree INSERT_LEAF`).

### Bước 4 — WAL Buffers

Record được copy vào **WAL buffers** (vùng shared memory, `wal_buffers`) tại vị trí đã đặt chỗ. Nhiều backend chèn song song vào đây.

### Bước 5 — COMMIT và WAL File

Khi COMMIT:

1. Backend chèn record `Transaction COMMIT`.
2. `XLogFlush(commit LSN)`: `write()` WAL buffers xuống **WAL segment file** trong `pg_wal/` (file 16MB tên như `000000010000000100000035`) rồi **`fsync()`** — đây là lúc dữ liệu thực sự bền vững. Nhiều transaction commit cùng lúc được gom vào một lần fsync (*group commit*).
3. Ghi trạng thái "committed" cho XID vào **`pg_xact`** (commit log).
4. Trả `COMMIT` cho client.

Với `synchronous_commit = on` (mặc định) client chỉ nhận OK sau fsync **cục bộ**. Với replication async, primary **không chờ** gì từ replica.

Data page vẫn dirty trong shared buffers; **checkpointer**/**bgwriter** sẽ ghi nó xuống `base/16384/16867` sau.

### Bước 6 — WAL Sender

Mỗi replica được phục vụ bởi một process **walsender** trên primary (thấy trong `ps` và `pg_stat_replication`). Sau khi WAL được flush, backend đánh thức walsender. Walsender **chỉ gửi WAL đã flush** trên primary: đọc từ WAL buffers/segment files, từ vị trí đã gửi (`sent_lsn`) tới flush LSN hiện tại.

### Bước 7 — TCP

WAL đi qua một kết nối libpq bình thường (cổng 5432) đã chuyển sang **replication protocol** bằng lệnh `START_REPLICATION SLOT replica_1_slot PHYSICAL 1/37000000`. Sau đó kết nối là một luồng `COPY` hai chiều:

- primary → replica: message **XLogData** (`w`): start LSN, end LSN, send time, *byte WAL nguyên bản*; và **keepalive** (`k`).
- replica → primary: **Standby Status Update** (`r`): write / flush / apply LSN; và **Hot Standby Feedback** (`h`): xmin.

Không có câu SQL nào được gửi — chỉ là byte WAL, vì vậy replica phải **cùng major version**.

### Bước 8 — WAL Receiver

Process **walreceiver** trên replica nhận XLogData, `write()` vào WAL segment tương ứng trong `pg_wal/` của replica (→ **write_lsn**), sau đó `fsync()` (→ **flush_lsn**). Sau mỗi lần ghi và ít nhất mỗi `wal_receiver_status_interval`, nó gửi status update về primary — đó là nguồn của các cột `write_lsn`, `flush_lsn`, `replay_lsn`, `*_lag` trong `pg_stat_replication`.

### Bước 9 — Replica WAL

Giờ WAL nằm bền vững trên đĩa replica. Nếu replica restart, nó replay tiếp từ đây và yêu cầu primary gửi từ vị trí flush cuối cùng.

### Bước 10 — Replay

Process **startup** (đang ở chế độ recovery vô hạn) đọc record kế tiếp từ `pg_wal`, gọi hàm *redo* của resource manager tương ứng:

- `Heap INSERT redo`: đọc block tham chiếu vào shared buffers của replica. Nếu **page LSN ≥ record LSN** → thay đổi đã có, bỏ qua (redo *idempotent*). Nếu record có FPI → chép nguyên trang. Ngược lại → chèn tuple đúng tại offset ghi trong record.
- Đặt page LSN = LSN record, đánh dấu dirty.

Xung đột: nếu record muốn xoá phiên bản dòng mà query trên replica còn cần (ví dụ record VACUUM cleanup), replay có thể phải **chờ** hoặc **huỷ** query đó — [mục 7](#7-xung-đột-truy-vấn-trên-replica).

### Bước 11 — Replica Data Page và tính khả kiến

Chèn tuple vào page **chưa** làm nó hiện ra với query trên replica. Phải đến khi startup process replay record **COMMIT**, XID mới được đánh dấu committed trong `pg_xact` của replica và bị xoá khỏi danh sách *KnownAssignedXids* (danh sách transaction đang chạy trên primary mà replica biết). Snapshot của query mới trên replica từ lúc đó sẽ thấy dòng mới. `pg_last_xact_replay_timestamp()` = thời điểm commit (theo đồng hồ primary) của transaction vừa replay.

Page dirty được ghi xuống `base/` của replica tại **restartpoint** (checkpoint phía standby).

### Bước 12 — Giải phóng WAL trên primary

Khi replica báo `flush_lsn` mới, primary tiến `restart_lsn` của slot. Tại checkpoint kế tiếp, segment WAL cũ hơn cả `restart_lsn`, `wal_keep_size` và điểm checkpoint được **tái sử dụng/xoá**.

### Tự quan sát

Xem đúng các WAL record một INSERT sinh ra (primary, extension `pg_walinspect`):

```sql
SELECT pg_current_wal_lsn() AS before_lsn \gset      -- trong DBeaver: chạy riêng và ghi lại giá trị
INSERT INTO replication_test (token) VALUES ('walinspect-demo');
SELECT pg_current_wal_lsn() AS after_lsn \gset

SELECT start_lsn, resource_manager, record_type, record_length, fpi_length, block_ref
FROM pg_get_wal_records_info(:'before_lsn', :'after_lsn');
```

Kết quả thật trong lab:

```text
 start_lsn  | resource_manager | record_type | record_length | fpi_length | block_ref
------------+------------------+-------------+---------------+------------+------------------------------------------------------------
 1/35648508 | Heap             | INSERT      |           246 |        192 | blkref #0: rel 1663/16384/16867 fork main blk 0 (FPW); ...
 1/35648600 | Btree            | INSERT_LEAF |           133 |         80 | blkref #0: rel 1663/16384/16873 fork main blk 1 (FPW); ...
 1/35648688 | Btree            | INSERT_LEAF |           157 |        104 | blkref #0: rel 1663/16384/16875 fork main blk 1 (FPW); ...
 1/35648728 | Transaction      | COMMIT      |          34 |          0 |
```

- 1 record `Heap INSERT` (bảng) + 2 record `Btree INSERT_LEAF` (PK `id` và UNIQUE `token`) + 1 `COMMIT`.
- `(FPW)`: có full page image vì đây là lần đầu các page này bị sửa sau checkpoint. Chạy INSERT lần nữa → `fpi_length = 0`, record nhỏ hơn nhiều.
- `16867` là relfilenode: `SELECT 'replication_test'::regclass::oid, pg_relation_filenode('replication_test');`

## 5. Giám sát: LSN, lag và từng metric

Tất cả truy vấn nằm trong [sql/monitoring/replication.sql](../sql/monitoring/replication.sql); `./scripts/check-replication.sh` chạy chúng giúp bạn.

### LSN là gì

**LSN** = vị trí byte (64 bit) trong dòng WAL vô tận của cluster, in dạng `hi/lo` hex: `1/35648508` = `0x1_35648508`. Hai LSN trừ nhau ra số byte:

```sql
SELECT pg_wal_lsn_diff('1/35648728', '1/35648508');   -- 544 byte WAL
SELECT pg_walfile_name('1/35648508');                 -- 000000010000000100000035
```

### Trên PRIMARY

| Hàm / cột | Ý nghĩa |
| --- | --- |
| `pg_current_wal_lsn()` | Vị trí WAL đã **ghi** (write) trên primary — "đầu" của dòng WAL. |
| `pg_current_wal_flush_lsn()` | Vị trí đã **fsync**. Walsender chỉ gửi tới đây. |
| `pg_current_wal_insert_lsn()` | Vị trí đã được đặt chỗ trong WAL buffers (có thể chưa ghi). |
| `pg_stat_replication.state` | `startup` → `catchup` (đang đuổi theo) → `streaming` (bắt kịp, gửi realtime). `backup` = một pg_basebackup. |
| `sent_lsn` | Đã gửi qua socket. |
| `write_lsn` | Replica đã `write()` (vào OS cache của nó, chưa bền). |
| `flush_lsn` | Replica đã `fsync()` (bền trên đĩa replica). Với sync replication mặc định (`synchronous_commit=on`) COMMIT chờ mốc này. |
| `replay_lsn` | Replica đã **replay** → dữ liệu nhìn thấy được trên replica. |
| `write_lag` / `flush_lag` / `replay_lag` | **Thời gian** từ lúc primary flush WAL tới lúc replica báo write/flush/replay. `NULL` khi hệ thống rảnh (không có WAL mới để đo). |
| `sync_state` | `async`, `sync`, `potential`, `quorum`. |
| `pg_replication_slots.restart_lsn` | WAL cũ nhất slot còn cần → mọi WAL từ đây trở đi bị giữ lại. |
| `pg_replication_slots.wal_status` | `reserved` / `extended` / `unreserved` / `lost`. |

**Lag theo byte** (chính xác, không phụ thuộc đồng hồ):

```sql
SELECT application_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn))   AS chua_gui,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, flush_lsn))              AS dang_tren_duong_hoac_chua_fsync,
       pg_size_pretty(pg_wal_lsn_diff(flush_lsn, replay_lsn))            AS da_nhan_chua_replay,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS tong_replay_lag
FROM pg_stat_replication;
```

Chẩn đoán nhanh:

- `chua_gui` lớn → walsender/mạng chậm.
- `dang_tren_duong...` lớn → mạng hoặc I/O ghi của replica chậm.
- `da_nhan_chua_replay` lớn → replay chậm, **hoặc bị chặn** bởi một query trên replica (xung đột), hoặc replay đang bị pause.

### Trên REPLICA

| Hàm | Ý nghĩa |
| --- | --- |
| `pg_is_in_recovery()` | `true` = đang là standby. |
| `pg_last_wal_receive_lsn()` | WAL cuối cùng walreceiver đã nhận **và fsync**. |
| `pg_last_wal_replay_lsn()` | WAL cuối cùng startup process đã replay. |
| `pg_last_xact_replay_timestamp()` | Thời điểm commit (đồng hồ primary) của transaction cuối đã replay. |
| `pg_stat_wal_receiver` | `status`, `sender_host`, `slot_name`, `flushed_lsn`, `latest_end_lsn` (vị trí cuối primary báo), `last_msg_receipt_time`. |
| `pg_is_wal_replay_paused()`, `pg_wal_replay_pause()`, `pg_wal_replay_resume()` | Tạm dừng / tiếp tục replay (WAL vẫn được **nhận**). |

**Lag theo thời gian nhìn từ replica — cái bẫy**:

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS since_last_replayed_commit;
```

Đây **không phải** lag: nếu primary không có transaction nào, con số này cứ tăng dù replica không hề trễ. Cách "vá" hay gặp trên mạng — trả về 0 khi `pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()` — cũng không đáng tin: `receive_lsn` có thể dừng ở giữa một WAL record chưa nhận đủ (primary mới flush tới biên trang WAL), record đó chưa replay được nên `replay_lsn` đứng ở record trước. Đo thật trên lab khi primary đứng yên: `receive_lsn = 0/70904000`, `replay_lsn = 0/70903A48`, công thức vá báo trễ **13 giây** trong khi replica đã replay xong mọi commit.

Cách đo đúng là **so với vị trí của primary**:

```sql
-- PRIMARY: byte lag + time lag do walsender đo (NULL khi không có WAL mới = không có gì để trễ)
SELECT application_name,
       pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;

-- REPLICA: chỉ có vị trí primary báo về gần nhất (latest_end_lsn), không phải vị trí hiện tại
SELECT pg_wal_lsn_diff(latest_end_lsn, pg_last_wal_replay_lsn()) AS behind_last_reported_bytes,
       latest_end_time
FROM pg_stat_wal_receiver;
```

`./scripts/check-replication.sh` đọc `pg_last_wal_replay_lsn()` trên replica, `pg_current_wal_lsn()` trên primary, rồi tính hiệu số.

### Thí nghiệm: nhìn thấy lag

```sql
-- REPLICA
SELECT pg_wal_replay_pause();

-- PRIMARY
INSERT INTO replication_test (token) VALUES ('while-paused');
SELECT application_name, pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn) AS bytes, replay_lag
FROM pg_stat_replication;
-- pglab-replica | 264 | 00:00:01.007   <- replay_lsn đứng yên

-- REPLICA
SELECT count(*) FROM replication_test WHERE token = 'while-paused';      -- 0 !
SELECT pg_get_wal_replay_pause_state(),
       pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()); -- paused | 264 : đã nhận, chưa replay
SELECT pg_wal_replay_resume();
SELECT count(*) FROM replication_test WHERE token = 'while-paused';      -- 1
```

## 6. Read / Write: primary vs replica

| Thao tác | Primary | Replica |
| --- | --- | --- |
| `SELECT` | ✅ | ✅ |
| `INSERT` / `UPDATE` / `DELETE` / `MERGE` / `TRUNCATE` | ✅ | ❌ `cannot execute INSERT in a read-only transaction` |
| `CREATE` / `ALTER` / `DROP` (kể cả `CREATE TEMP TABLE`) | ✅ | ❌ `cannot execute CREATE TABLE in a read-only transaction` |
| `SELECT ... FOR UPDATE / FOR SHARE` | ✅ | ❌ `cannot execute SELECT FOR UPDATE in a read-only transaction` |
| `nextval()` | ✅ | ❌ `cannot execute nextval() in a read-only transaction` |
| `VACUUM`, `ANALYZE` | ✅ | ❌ `cannot execute VACUUM during recovery` (nhận kết quả VACUUM của primary qua WAL) |
| `EXPLAIN ANALYZE SELECT` | ✅ | ✅ (thống kê planner là bản sao của primary) |
| `pg_stat_statements`, `pg_stat_activity` | ✅ | ✅ nhưng **riêng từng node** |
| `ALTER SYSTEM`, `pg_reload_conf()` | ✅ | ✅ (chỉ ghi file cấu hình cục bộ, không đụng WAL) |

Thử:

```sql
-- kết nối localhost:5433
INSERT INTO replication_test (token) VALUES ('x');
-- ERROR:  cannot execute INSERT in a read-only transaction
SHOW transaction_read_only;          -- on
SHOW default_transaction_read_only;  -- off  (không phải do cấu hình, mà vì đang recovery)
```

**Tại sao replica không thể ghi?**

1. **Chỉ có một dòng WAL**. Data directory của replica phải là bản sao từng byte của primary để WAL record "block 1234, offset 5" áp đúng chỗ. Một lệnh ghi cục bộ sẽ làm page của replica khác primary → các record tiếp theo áp sai → dữ liệu hỏng.
2. **Không có XID riêng**. XID do primary cấp. Replica tự cấp XID sẽ trùng với XID primary cấp cho transaction khác → MVCC sai hoàn toàn.
3. **Không có WAL riêng**. Mọi thay đổi bền vững phải qua WAL; replica chỉ *nhận* WAL, nó không có "đầu ghi" của mình trong khi recovery.

Vì vậy PostgreSQL chặn ngay ở tầng executor: mọi transaction trên standby tự động là `READ ONLY`.

**Hệ quả với ứng dụng (read/write splitting)**: replication async ⇒ **read-your-writes không được đảm bảo**. User vừa đặt hàng (ghi primary) rồi mở trang "đơn của tôi" (đọc replica) có thể không thấy đơn trong vài ms (hoặc lâu hơn nếu replica trễ). Cách xử lý thường gặp: đọc từ primary trong N giây sau khi ghi, hoặc chờ replica đạt LSN của lần ghi (`pg_last_wal_replay_lsn() >= lsn`), hoặc dùng sync replication với `synchronous_commit = remote_apply`.

Driver hỗ trợ tự chọn node: libpq `target_session_attrs=read-write|read-only|primary|standby`:

```text
postgresql://postgres:postgres@localhost:5432,localhost:5433/ecommerce?target_session_attrs=read-write
```

## 7. Xung đột truy vấn trên replica

Primary không biết (mặc định) replica đang đọc gì. Ví dụ: một query dài trên replica đang đọc phiên bản cũ của dòng X; trên primary, VACUUM xoá phiên bản đó và ghi WAL `PRUNE`. Khi replay tới record này, startup process có 2 lựa chọn: chờ query xong (replica trễ dần) hay huỷ query. PostgreSQL chờ tối đa `max_standby_streaming_delay` rồi huỷ:

```text
ERROR:  canceling statement due to conflict with recovery
DETAIL:  User query might have needed to see row versions that must be removed.
```

Lab này bật `hot_standby_feedback = on` nên primary giữ lại các phiên bản mà replica còn cần (xem `pg_replication_slots.xmin` hoặc `pg_stat_replication.backend_xmin`) → xung đột kiểu *snapshot* gần như biến mất, đổi lại VACUUM trên primary bị "giữ chân". Các xung đột khác (lock khi `DROP TABLE`/`ALTER TABLE` trên primary, tablespace, buffer pin) vẫn xảy ra.

Thống kê huỷ query: `SELECT * FROM pg_stat_database_conflicts WHERE datname = 'ecommerce';` (trên replica).

Bài tập ở [mục 11](#11-bài-tập).

## 8. Replication slot

Không có slot, primary chỉ giữ `wal_keep_size` WAL. Replica tắt lâu, primary sinh nhiều WAL → segment replica cần đã bị xoá → replica không bao giờ bắt kịp được:

```text
FATAL:  could not receive data from WAL stream: ERROR:  requested WAL segment 00000001000000010000002A has already been removed
```

Có slot, primary giữ **mọi** WAL từ `restart_lsn`. Rủi ro ngược lại: slot của replica đã chết giữ WAL mãi → **đầy đĩa primary** → primary dừng. `max_slot_wal_keep_size = 4GB` là cầu chì: vượt ngưỡng thì slot chuyển `wal_status = lost` và replica phải rebuild.

```sql
SELECT slot_name, active, restart_lsn, wal_status,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained,
       pg_size_pretty(safe_wal_size) AS con_ghi_duoc_truoc_khi_lost
FROM pg_replication_slots;
```

## 9. Synchronous replication

```sql
-- PRIMARY: tên phải khớp application_name (= cluster_name của replica).
-- Có dấu '-' nên phải đặt trong dấu nháy kép:
ALTER SYSTEM SET synchronous_standby_names = '"pglab-replica"';
SELECT pg_reload_conf();
SELECT application_name, sync_state FROM pg_stat_replication;   -- sync
```

Giờ COMMIT trên primary chỉ trả về khi replica đã **flush** WAL (mức mặc định `synchronous_commit = on`). Các mức khác:

| `synchronous_commit` | COMMIT chờ tới khi | Mất dữ liệu nếu primary chết? |
| --- | --- | --- |
| `off` | không chờ cả fsync cục bộ | có thể mất vài trăm ms giao dịch gần nhất (không hỏng dữ liệu) |
| `local` | fsync cục bộ | có (replica chưa nhận) |
| `remote_write` | replica `write()` (OS cache) | chỉ khi cả hai cùng sập |
| `on` | replica `fsync()` | không |
| `remote_apply` | replica **replay** xong | không, và đọc ngay trên replica thấy dữ liệu |

Thí nghiệm "replica sync biến mất":

```bash
docker compose stop postgres-replica
```

```sql
-- PRIMARY, session A
INSERT INTO replication_test (token) VALUES ('sync-demo');   -- TREO
-- session B
SELECT pid, wait_event_type, wait_event, state, query FROM pg_stat_activity WHERE wait_event = 'SyncRep';
--  1153 | IPC | SyncRep | active | insert into replication_test ...
SELECT pg_cancel_backend(1153);
-- session A nhận:
-- WARNING:  canceling wait for synchronous replication due to user request
-- DETAIL:  The transaction has already committed locally, but might not have been replicated to the standby.
```

Hai bài học:

1. Sync replication với **một** standby = standby chết thì mọi ghi trên primary treo. Thực tế dùng `ANY 1 (r1, r2)` với ≥ 2 standby.
2. Transaction **đã commit cục bộ** trước khi chờ; huỷ việc chờ không rollback được. (`statement_timeout` cũng không huỷ được giai đoạn chờ này — phải `pg_cancel_backend`.)

Trả lại async và bật replica:

```sql
ALTER SYSTEM RESET synchronous_standby_names;
SELECT pg_reload_conf();
```

```bash
docker compose start postgres-replica
```

## 10. Failover

**Failover** = primary chết, đưa replica lên làm primary (**promote**). PostgreSQL chỉ cung cấp cơ chế promote; việc *phát hiện* primary chết, *quyết định* promote và *chuyển hướng* client là việc của công cụ bên ngoài (Patroni, repmgr, pg_auto_failover, Stolon, dịch vụ managed như RDS/Cloud SQL).

### Promote bằng tay

```sql
-- REPLICA (localhost:5433)
SELECT pg_promote(wait => true);                   -- hoặc: docker compose exec -u postgres postgres-replica pg_ctl promote
SELECT pg_is_in_recovery();                         -- false
SELECT pg_walfile_name(pg_current_wal_lsn());       -- 00000002...  <- timeline 2
INSERT INTO replication_test (token) VALUES ('written-on-promoted-replica');   -- thành công
```

Điều gì đã xảy ra:

1. Startup process replay nốt WAL đã nhận, ngừng recovery, xoá `standby.signal`.
2. Chuyển sang **timeline mới** (1 → 2) và ghi file lịch sử `00000002.history` — WAL từ đây rẽ nhánh khỏi primary cũ.
3. Nhận ghi, cấp XID, autovacuum chạy... Nó là một primary độc lập.

Trên primary cũ: `SELECT count(*) FROM pg_stat_replication;` → `0`.

### Split-brain

Giờ có **hai primary** cùng nhận ghi (nếu app vẫn ghi vào cả hai) → dữ liệu phân kỳ, không tự hợp nhất được. Đây là rủi ro lớn nhất của failover; hệ thống thật dùng *fencing* (tắt hẳn primary cũ, STONITH) và cơ chế đồng thuận (etcd/Consul trong Patroni) để đảm bảo chỉ có một primary.

### Đưa node về lại làm replica

Primary cũ **không thể** đơn giản trỏ vào primary mới: nó có thể có WAL chưa kịp gửi đi (phần đã phân kỳ). Hai cách:

- **`pg_rewind`**: tua data directory của node cũ về điểm rẽ nhánh rồi lấy phần thay đổi từ node mới (cần `wal_log_hints = on` hoặc data checksums — lab đã bật).
- **Rebuild**: xoá sạch, `pg_basebackup` lại.

Trong lab, sau khi promote replica, đưa mọi thứ về cấu hình ban đầu (primary gốc vẫn là primary, replica clone lại):

```bash
./scripts/rebuild-replica.sh        # xoá volume replica, đảm bảo slot tồn tại, pg_basebackup lại
./scripts/check-replication.sh
```

Dòng `written-on-promoted-replica` biến mất — nó chỉ tồn tại trên nhánh timeline 2 đã bị bỏ. Đó chính là "mất dữ liệu" do split-brain.

Nếu restart một replica đã promote mà chưa rebuild, entrypoint cảnh báo:

```text
[replica-entrypoint] WARNING: standby.signal is missing -> this node was PROMOTED and will start as a read-write primary.
```

### Các khái niệm cần biết

| Khái niệm | Ý nghĩa |
| --- | --- |
| **RPO** (Recovery Point Objective) | Chấp nhận mất tối đa bao nhiêu dữ liệu. Async: có thể mất WAL chưa gửi (≈ lag lúc chết). Sync: 0. |
| **RTO** (Recovery Time Objective) | Mất bao lâu để hệ thống ghi lại được: phát hiện + promote + chuyển client. |
| **Switchover** | Chuyển vai trò *có kế hoạch* (bảo trì): dừng primary sạch sẽ → replica nhận hết WAL → promote → primary cũ làm replica. Không mất dữ liệu. |
| **Timeline** | Mỗi lần promote tạo timeline mới; replica theo dõi timeline qua `recovery_target_timeline = 'latest'` (mặc định). |
| **Cascading replication** | Replica stream WAL cho replica khác (giảm tải primary). |
| **Delayed replica** | `recovery_min_apply_delay` — cứu khỏi thao tác sai kiểu `DROP TABLE`. |

## 11. Bài tập

1. Chạy `./scripts/check-replication.sh` và giải thích từng cột của `pg_stat_replication`.
2. Trên primary, dùng `pg_walinspect` so sánh WAL sinh ra bởi: (a) `INSERT` 1 dòng, (b) `UPDATE products SET price = price WHERE id = 1` (HOT update?), (c) `UPDATE products SET sku = sku || '' WHERE id = 1`, (d) `DELETE`. Record nào xuất hiện? Có FPI không?
3. Đo lượng WAL của `UPDATE products SET price = price * 1.01 WHERE category_id = 12;` (dùng `pg_current_wal_lsn()` trước/sau). So với kích thước các trang bị sửa.
4. Pause replay trên replica, chạy một `UPDATE` lớn trên primary, quan sát 3 loại lag byte ở [mục 5](#5-giám-sát-lsn-lag-và-từng-metric), rồi resume và xem replica bắt kịp.
5. Tắt replica (`docker compose stop postgres-replica`), chạy `docker compose run --rm -e RESET_DATA=true data-generator` (sinh ~2–3 GB WAL). Quan sát `retained_wal` và `wal_status` của slot trong lúc đó. Bật replica lại và đo thời gian catch-up (`state = catchup` → `streaming`).
6. Xung đột recovery: trên replica `ALTER SYSTEM SET hot_standby_feedback = off; SELECT pg_reload_conf();` và `ALTER SYSTEM SET max_standby_streaming_delay = '5s'`. Trên replica mở `BEGIN ISOLATION LEVEL REPEATABLE READ; SELECT count(*) FROM products;` (giữ transaction mở). Trên primary `UPDATE products SET price = price WHERE id <= 5000; VACUUM products;`. Quay lại replica chạy `SELECT count(*) FROM products;` → lỗi gì? Xem `pg_stat_database_conflicts`. Nhớ `ALTER SYSTEM RESET ...` hai tham số sau khi xong.
7. Sync replication: làm lại thí nghiệm [mục 9](#9-synchronous-replication) với `SET synchronous_commit = remote_apply` và `local` ở mức session; đo thời gian INSERT (`\timing` trong psql).
8. Failover: promote replica, ghi vào cả hai node (split-brain), so sánh `pg_walfile_name(pg_current_wal_lsn())` hai bên, rồi `./scripts/rebuild-replica.sh`.
9. Kết nối bằng connection string nhiều host với `target_session_attrs=read-write` rồi `=read-only`, và kiểm tra mình đang ở node nào:

   ```bash
   docker compose exec -e PGPASSWORD=postgres postgres-primary psql \
     "host=postgres-primary,postgres-replica user=postgres dbname=ecommerce target_session_attrs=read-only" \
     -c "SELECT current_setting('cluster_name'), pg_is_in_recovery()"
   #  pglab-replica | t      (với read-write -> pglab-primary | f)
   ```

   Promote replica rồi thử lại: `read-write` giờ chọn được node nào?
10. Physical backup: `docker compose exec -u postgres postgres-primary pg_basebackup -D /tmp/bb -Ft -z -Xs -P` — so sánh với `pg_dump` ([backup-restore.md](backup-restore.md)).
