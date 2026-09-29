# PART 44 — COMMON DATABASE MYTHS

> **Trước:** [43 — Data Engineer Perspective](43-data-engineer-perspective.md) · **Tiếp:** [45 — Interview Handbook](45-interview-handbook.md)

Mỗi myth được đánh giá **Đúng / Sai / Đúng một phần**, kèm **cơ chế** giải thích và chương tham chiếu. Mục tiêu không phải thuộc lòng đáp án, mà để thấy mỗi myth sai ở **mắt xích internal nào**.

---

## Mục lục

| # | Myth | Kết luận |
|---|---|---|
| 1 | Index luôn làm query nhanh hơn | Sai |
| 2 | Replica luôn giống Primary ngay lập tức | Sai |
| 3 | DELETE xóa dữ liệu ngay | Sai |
| 4 | UPDATE overwrite row cũ | Sai |
| 5 | COUNT(*) luôn scan toàn bộ table | Đúng một phần |
| 6 | Serializable nghĩa là chạy transaction lần lượt | Sai |
| 7 | Read replica giúp scale write | Sai |
| 8 | Partitioning = sharding | Sai |
| 9 | Cluster = replica | Sai |
| 10 | VACUUM khóa toàn bộ table | Sai (trừ VACUUM FULL) |
| 11 | PostgreSQL chỉ cache trong shared_buffers | Sai |
| 12 | CAP nghĩa là chọn 2 trong 3 | Sai |
| 13–30 | Các myth bổ sung | |

---

## 1. "Index luôn làm query nhanh hơn." — **Sai**

**Cơ chế:**
- Index scan đọc heap theo **random I/O** (mỗi TID có thể là một page khác). Khi query cần phần lớn table (selectivity cao), **seq scan** (đọc tuần tự, không overhead index) nhanh hơn ([Chương 15 §9.4](15-index-internals.md#94-seq-scan-vs-index-scan-vs-bitmap--theo-selectivity), [17 §9.3](17-query-planner.md#93-index-scan-cost-đơn-giản-hóa-cost_index--btcostestimate)).
- Index **không có visibility** → vẫn phải đọc heap (trừ index-only scan với VM).
- Index làm **ghi chậm hơn**: mỗi INSERT/UPDATE non-HOT phải cập nhật mọi index, sinh WAL, có thể split; index trên cột hay đổi **phá HOT** ([Chương 24](24-hot-update.md)).
- Index chiếm cache, làm vacuum lâu hơn (quét mọi index).
- Index sai cột/thứ tự cột không giúp gì ([Chương 16](16-composite-index.md)).

**Đúng là:** index giúp query **đọc ít row** theo điều kiện/thứ tự phù hợp, với chi phí ở đường ghi.

---

## 2. "Replica luôn giống Primary ngay lập tức." — **Sai**

**Cơ chế:** WAL phải đi qua send → network → write → flush → **replay** ([Chương 28](28-replication-lag.md)); replay single-threaded, có thể bị recovery conflict chặn. Async replication: primary trả commit **trước** khi replica nhận. Ngay cả sync `on`: standby đã flush nhưng **chưa replay** → đọc từ standby chưa thấy; chỉ `remote_apply` đảm bảo thấy.

**Đúng là:** replica hiển thị một **prefix nhất quán** của lịch sử primary, **trễ** một khoảng biến động.

---

## 3. "DELETE xóa dữ liệu ngay." — **Sai**

**Cơ chế:** DELETE chỉ đặt `xmax` trên tuple ([Chương 07 §5](07-read-write-behavior.md#5-delete)). Tuple vẫn nằm trên page, index vẫn trỏ tới, cho tới khi (1) transaction commit, (2) không còn snapshot nào cần (xmin horizon), (3) pruning/VACUUM dọn. Plain VACUUM chỉ biến chỗ đó thành **chỗ trống tái sử dụng**, không trả disk cho OS (trừ page trống cuối file). Dữ liệu "đã xóa" còn tồn tại vật lý (quan trọng cho bảo mật/GDPR — cần VACUUM/rewrite và quản lý backup).

**Muốn giải phóng disk:** DROP/TRUNCATE (file mới), DROP PARTITION, VACUUM FULL/pg_repack.

---

## 4. "UPDATE overwrite row cũ." — **Sai**

**Cơ chế:** UPDATE = đặt `xmax` trên version cũ + ghi **version mới đầy đủ** với `xmin` mới ([Chương 07 §4](07-read-write-behavior.md#4-update), [11](11-mvcc.md)). Version cũ ở lại cho snapshot cũ; non-HOT update thêm entry vào **mọi** index. Hệ quả chuỗi: **UPDATE → MVCC → dead tuple → VACUUM → (không kịp) bloat → I/O → query chậm**. (InnoDB update in-place và lưu before-image vào undo — đây là khác biệt kiến trúc.)

---

## 5. "COUNT(*) luôn scan toàn bộ table." — **Đúng một phần**

**Đúng ở chỗ:** PostgreSQL **không lưu** số row chính xác, vì mỗi transaction (snapshot khác nhau) có thể thấy số row khác nhau — MVCC ([Chương 11](11-mvcc.md)). `COUNT(*)` phải đếm các tuple **visible** với snapshot hiện tại. Không có "bộ đếm metadata" như MyISAM.

**Không hoàn toàn đúng ở chỗ:**
- Planner có thể dùng **Index Only Scan** trên index nhỏ nhất (đọc ít page hơn heap) nếu **VM** đánh dấu phần lớn page all-visible (Heap Fetches thấp).
- **Parallel** Seq Scan/Index Only Scan chia việc cho nhiều worker.
- `COUNT(*) WHERE ...` với index phù hợp chỉ đọc phần liên quan.
- Cần số **gần đúng**: `SELECT reltuples FROM pg_class WHERE relname = 't'` (cập nhật bởi VACUUM/ANALYZE) hoặc ước lượng của EXPLAIN — O(1).

**Hệ quả thiết kế:** "hiển thị tổng số trang" trên table lớn nên dùng số ước lượng, hoặc counter được duy trì (cẩn thận hot row).

---

## 6. "Serializable nghĩa là chạy transaction lần lượt." — **Sai**

**Cơ chế:** Serializable đảm bảo **kết quả tương đương** một thứ tự tuần tự **nào đó**, không phải thực thi tuần tự. PostgreSQL dùng **SSI**: các transaction chạy **song song** trên snapshot, SIRead predicate lock ghi lại phụ thuộc đọc–ghi, và **abort** (40001) khi phát hiện cấu trúc nguy hiểm ([Chương 12 §8](12-isolation-level.md#8-serializable--ssi)). SSI không thêm lock chặn — reader không chờ writer.

---

## 7. "Read replica giúp scale write." — **Sai**

**Cơ chế:** Mọi ghi vẫn đi vào **một primary**; mỗi replica phải **replay toàn bộ WAL** của primary ([Chương 26 §4](26-primary-replica.md#4-write-path)). Replica còn tăng nhẹ tải primary (walsender) và có thể gây bloat (hot_standby_feedback). Replica chỉ **gián tiếp** giúp ghi bằng cách lấy bớt tải **đọc** khỏi primary. Scale ghi cần: giảm chi phí ghi, tách service, **sharding**.

---

## 8. "Partitioning = sharding." — **Sai**

**Cơ chế:** Partition là nhiều table vật lý **trong cùng một database/server** — chung WAL, buffer, transaction manager; PostgreSQL tự route; giữ ACID/FK/join. Shard là dữ liệu trên **nhiều server độc lập** — cần router ngoài, mất transaction/join/unique toàn cục, failure domain riêng, scale tài nguyên ([Chương 34](34-partitioning-vs-sharding.md)).

---

## 9. "Cluster = replica." — **Sai**

**Cơ chế:** "Database cluster" trong PostgreSQL là **một instance** (một PGDATA) chứa nhiều database. "HA cluster" gồm primary + replica. "Distributed cluster" chia dữ liệu giữa node. Lệnh `CLUSTER` sắp xếp lại table. Kubernetes cluster là hạ tầng ([Chương 35](35-database-cluster.md)).

---

## 10. "VACUUM khóa toàn bộ table." — **Sai** (trừ VACUUM FULL)

**Cơ chế:** Plain VACUUM (và autovacuum) lấy **SHARE UPDATE EXCLUSIVE** — **không** xung đột với SELECT/INSERT/UPDATE/DELETE; chỉ xung đột với DDL, VACUUM khác, CREATE INDEX ([Chương 13 §4](13-locking.md#4-concept-table-level-locks), [23](23-vacuum.md)). Có hai điểm lock ngắn cần biết: pha **truncate** cuối file lấy ACCESS EXCLUSIVE **có điều kiện** (bỏ qua nếu tranh chấp; trên standby có thể gây conflict); và vacuum cần **cleanup lock** trên từng page (không chặn người khác, tự bỏ qua page đang bị pin).

**VACUUM FULL** thì **đúng là** khóa ACCESS EXCLUSIVE toàn bộ table suốt thời gian rewrite.

---

## 11. "PostgreSQL chỉ cache trong shared_buffers." — **Sai**

**Cơ chế:** PostgreSQL dùng **buffered I/O** — mọi đọc/ghi đi qua **OS page cache** ([Chương 08 §9](08-memory-buffer-cache.md#9-concept-shared-buffers-vs-os-page-cache-vs-disk)). "Miss" ở shared_buffers thường là "hit" ở page cache. Vì vậy shared_buffers thường chỉ ~25% RAM, phần còn lại để OS cache; `effective_cache_size` báo cho planner tổng cache. (Khác InnoDB dùng O_DIRECT và buffer pool 70–80% RAM.)

---

## 12. "CAP nghĩa là chọn 2 trong 3." — **Sai**

**Cơ chế:** CAP (Gilbert & Lynch) nói: **khi có network partition**, hệ phân tán không thể vừa **linearizable** vừa đảm bảo **mọi node không lỗi đều phản hồi**. Partition không phải thứ được "chọn" — nó xảy ra. Câu hỏi thực: khi partition, hy sinh C hay A? Khi không partition, trade-off là latency vs consistency (PACELC) ([Chương 38 §8](38-consistency.md#8-cap--phát-biểu-chính-xác)). C của CAP là linearizability, không phải C của ACID.

---

## Myth bổ sung

| # | Myth | Kết luận | Cơ chế ngắn | Chương |
|---|---|---|---|---|
| 13 | "Nên chạy VACUUM FULL định kỳ." | Sai | Khóa toàn table, cần 2× chỗ; bloat steady-state là bình thường; dùng autovacuum tốt + pg_repack khi cần | [23](23-vacuum.md) |
| 14 | "Lỗi too many clients → tăng max_connections." | Sai (thường) | Connection là process; nhiều active → contention; gốc thường là query chậm/idle in tx; dùng pooler | [37](37-connection-management.md) |
| 15 | "Checkpoint làm dữ liệu an toàn." | Sai | Durability đến từ WAL flush lúc commit; checkpoint rút ngắn recovery, cho phép recycle WAL | [21](21-checkpoint.md) |
| 16 | "SELECT không bao giờ ghi disk." | Sai | Hint bits (có thể FPI với checksums), HOT pruning, kill index tuple, temp file | [06](06-storage-internals.md), [07](07-read-write-behavior.md) |
| 17 | "work_mem là giới hạn mỗi connection." | Sai | Giới hạn **mỗi node** sort/hash; một query có thể dùng nhiều lần, × parallel worker | [04](04-postgresql-architecture.md) |
| 18 | "Primary key là clustered index." | Sai (với PostgreSQL) | Heap không có thứ tự; PK là unique B-Tree như mọi index | [01](01-relational-database.md) |
| 19 | "Foreign key tự tạo index ở table con." | Sai | Chỉ PK/UNIQUE ở table cha có index; thiếu index FK → DELETE cha seq scan con | [01](01-relational-database.md) |
| 20 | "Rollback một transaction lớn rất chậm." | Sai (PostgreSQL) | Rollback O(1) qua CLOG; cái giá là dead tuple để lại | [09](09-transaction.md) |
| 21 | "`WHERE col = NULL` tìm row NULL." | Sai | Logic ba giá trị; dùng `IS NULL`; `NOT IN` + NULL trả rỗng | [01](01-relational-database.md) |
| 22 | "CTE luôn là optimization fence." | Sai từ PG 12 | CTE không đệ quy, không side effect, dùng một lần được inline | [03](03-sql.md) |
| 23 | "Planner luôn chọn plan tối ưu." | Sai | Chọn rẻ nhất **theo ước lượng**; thống kê/giả định độc lập có thể sai nhiều bậc | [17](17-query-planner.md) |
| 24 | "Sync replication = đọc replica luôn thấy dữ liệu mới." | Sai | Chỉ `remote_apply`; `on` chỉ đảm bảo flush | [27](27-sync-async-replication.md) |
| 25 | "Read Uncommitted cho dirty read trong PostgreSQL." | Sai | Được xử lý như Read Committed | [12](12-isolation-level.md) |
| 26 | "Hash index không an toàn." | Sai từ PG 10 | WAL-logged, crash-safe, replicate được | [15](15-index-internals.md) |
| 27 | "`SELECT *` vô hại." | Sai | Detoast cột lớn, ngăn index-only scan, tăng network; view `SELECT *` không nhận cột mới | [06](06-storage-internals.md) |
| 28 | "UUID làm PK không có chi phí." | Sai | UUIDv4 ngẫu nhiên → insert rải khắp B-Tree, cache kém, FPI; UUIDv7 giảm vấn đề | [01](01-relational-database.md), [15](15-index-internals.md) |
| 29 | "Có thể tắt autovacuum để tăng hiệu năng." | Sai | Bloat, stats cũ; anti-wraparound vẫn buộc chạy vào lúc tệ nhất | [23](23-vacuum.md) |
| 30 | "Càng nhiều index càng tốt." | Sai | Write amplification, mất HOT, vacuum lâu, cache chia nhỏ | [15](15-index-internals.md), [24](24-hot-update.md) |
| 31 | "Replica là backup." | Sai | Replica nhân bản lỗi logic ngay lập tức; cần PITR | [31](31-backup-pitr.md) |
| 32 | "Partition luôn làm query nhanh hơn." | Sai | Query không có partition key phải chạm mọi partition; overhead planning/lock | [32](32-partitioning.md) |
| 33 | "Transaction read-only không ảnh hưởng ai." | Sai | Giữ snapshot → giữ xmin horizon → chặn vacuum; giữ AccessShareLock → chặn DDL | [11](11-mvcc.md), [13](13-locking.md) |
| 34 | "Sequence không có lỗ." | Sai | nextval không rollback; cache/log theo lô → nhảy số sau crash/failover | [01](01-relational-database.md) |
| 35 | "PostgreSQL tự failover." | Sai | Core không có automatic failover; cần Patroni/operator | [29](29-high-availability.md) |

---

## Interview Questions

**Q1. Chọn ba myth phổ biến nhất bạn từng gặp và giải thích vì sao sai.**
- *Gợi ý:* "UPDATE overwrite" (MVCC), "index luôn nhanh hơn" (selectivity, write cost), "replica scale write" (replay mọi WAL).

**Q2. Tại sao PostgreSQL không lưu sẵn COUNT(*)?**
- *Short:* MVCC: mỗi snapshot thấy số row khác; bộ đếm chung sẽ là hot row và vẫn sai theo snapshot.

**Q3. VACUUM có chặn ứng dụng không?**
- *Short:* Plain VACUUM không chặn DML (SHARE UPDATE EXCLUSIVE); VACUUM FULL chặn mọi thứ; truncate phase lock ngắn có điều kiện.

---

## Key Takeaways

1. Phần lớn myth sai vì **bỏ qua MVCC** (UPDATE/DELETE/COUNT/VACUUM), **bỏ qua WAL/replication pipeline** (replica, checkpoint, sync), hoặc **nhầm thuật ngữ** (cluster, partition/shard, CAP consistency).
2. Khi nghe một khẳng định tuyệt đối ("luôn", "không bao giờ") về database, hãy hỏi: **cơ chế nào** đứng sau, và **điều kiện nào** làm nó sai.

---

## Nguồn tham khảo

- PostgreSQL Docs (các chương tương ứng đã dẫn).
- PostgreSQL Wiki — *Don't Do This*: https://wiki.postgresql.org/wiki/Don%27t_Do_This
- PostgreSQL Wiki — *Slow Counting*: https://wiki.postgresql.org/wiki/Slow_Counting
- Martin Kleppmann, *A Critique of the CAP Theorem* (2015).
