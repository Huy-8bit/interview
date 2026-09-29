# Design Migration Platform — 4–5 Billion Records

## Bài toán và ví dụ đầu tiên

Migrate 4–5 tỷ records trong khi source vẫn nhận writes là bài toán giữ snapshot, change stream và verification cùng một mô hình tiến trình. Copy thật nhanh mà thiếu boundary giữa snapshot và changes có thể mất update hoặc hồi sinh record đã delete.

## Đi từng bước qua một tình huống

Phiên bản 1 thử trên một dataset nhỏ với một worker, source snapshot nhất quán và target idempotent upsert. Ghi manifest/checkpoint bền theo range, source position/version và transform version. Xác minh counts/checksums theo partition và mẫu semantic fields. API/UI chỉ điều khiển job; nó không quyết định correctness của data plane.

Phiên bản 2 chia snapshot thành ranges có ownership/lease và bounded workers. Capacity dựa source read budget, network, target write/index cost và retention change log, không chỉ số goroutine. Checkpoint chỉ tiến qua dữ liệu đã ghi và kiểm chứng theo contract; worker restart replay cùng range phải an toàn.

## Hiểu cơ chế từ kết quả quan sát

Phiên bản 3 phối hợp snapshot với CDC — change data capture, luồng thay đổi sau một position được xác định. Phải chọn thuật toán boundary theo source/connector để không gap giữa snapshot và log, và áp version/order để snapshot cũ không overwrite change mới. Kafka có thể là buffer/replay log cho CDC nếu requirements cần, nhưng thêm nó không tự giải quyết snapshot consistency.

Ví dụ 5 tỷ rows × 1 KB khoảng 5 TB payload thô theo đơn vị thập phân, chưa indexes/replicas/protocol. 50000 rows/s cần tối thiểu khoảng 100000 giây, hơn 27 giờ, nếu rate giữ ổn định và chưa tính catch-up/verification. Source log retention phải che tổng thời gian cùng failure margin; nếu tụt ra ngoài retention, cần chiến lược resnapshot chứ không tiếp tục như không có gap.

**Design lab:** các con số dưới đây là giả định để ước lượng, chưa phải kết quả benchmark. Xác nhận semantics và workload trước khi chọn hạ tầng.

## Requirements

Migrate 4–5 tỷ records từ Source DB sang Target DB với snapshot song song CDC, transformation versioned, checkpoints, retry/DLQ và verification. Source vẫn nhận writes trong migration; cutover có rollback plan và ownership rõ.

## Non-functional Requirements

Không mất committed changes trong phạm vi snapshot+CDC protocol; per-key final state/order đúng; deletes được propagate; schema evolution có control. Giả định window72h cho snapshot5B, CDC peak20k changes/s, cutover lag<30s và zero unexplained verification mismatches.

## Capacity Estimation

5B/72h≈19,290 snapshot rows/s; chọn planning target 25k/s để có headroom trước validation/retries, không claim measured. Mean raw row1KiB →~4.66TiB snapshot chưa index/encoding;25k rows/s≈24.4MiB/s raw. Nếu transform+write throughput40k/s tổng và CDC consumes20k/s thì snapshot còn20k/s, chỉ vừa theoretical window. Cần capacity riêng hoặc kéo dài window. 24h CDC buffer ở20k/s×1KiB≈1.61TiB raw trước replication; Kafka replication3x≈4.83TiB cộng overhead/retention reserve.

## API

POST /migrations {source_ref,target_ref,tables,transform_version}; GET /migrations/{id}/progress; POST pause/resume; POST verify; POST cutover với verification revision và operator authorization. Secrets qua references, không trong request payload.

## Data Model

migrations(id,state,source_boundary,transform_version,schema_version); chunks(table,key_start,key_end,snapshot_boundary,status,checkpoint,checksum); source events có source_position,transaction_id,table,primary_key,op,schema_version; target applied_version per entity và processed_event ID khi cần; DLQ chứa cause và original position.

## High-Level Architecture

```mermaid
flowchart LR
    S[Source DB] --> SN[Consistent snapshot chunks]
    S --> CDC[CDC at coordinated boundary]
    SN --> K[Kafka or durable staging]
    CDC --> K
    K --> W[Bounded Go workers]
    W --> T[Versioned transformation]
    T --> D[Target DB]
    W --> C[Durable checkpoints]
    D --> V[Verification and cutover controller]
```

### Cách đọc diagram

Source cấp snapshot chunks và CDC tại boundary phối hợp; cả hai vào durable staging/log rồi bounded Go workers transform sang target. Workers giữ checkpoints, target được verification/cutover controller kiểm tra. Hai luồng nguồn phải có ordering/version semantics để snapshot cũ không ghi đè change mới.

## Request Flow

Coordinator chốt source-specific snapshot/CDC boundary. Một cách triển khai: giữ CDC từ boundary, đọc consistent snapshot, load snapshot trước, rồi replay mọi changes từ boundary theo order. Hoặc interleave chỉ khi protocol target versions bảo đảm snapshot cũ không overwrite CDC mới. Không lấy snapshot và “bắt đầu CDC sau đó” vì có gap. Multi-table transaction atomicity cần explicit transaction grouping nếu business yêu cầu, per-key order alone chưa đủ.

```mermaid
sequenceDiagram
    participant C as Coordinator
    participant S as Source DB and CDC
    participant K as Durable log
    participant W as Go Workers
    participant T as Target DB
    C->>S: Establish snapshot and CDC boundary
    S->>K: Snapshot chunks plus concurrent changes
    K->>W: Partitioned versioned events
    W->>T: Apply batch and progress atomically where possible
    T-->>W: Commit durable state
    W->>K: Commit contiguous consumed progress
    C->>T: Verify then authorize cutover
```

### Cách đọc diagram

Coordinator thiết lập snapshot/CDC boundary với source, rồi source ghi snapshot và concurrent changes vào durable log. Workers apply batch/progress atomically khi cùng boundary cho phép, chỉ commit contiguous consumed progress sau durable target commit. Cutover diễn ra sau verification, không chỉ khi queue nhìn có vẻ trống.

## Data Flow

```mermaid
flowchart TD
    S[Source row or tombstone] --> E[Envelope with key and source position]
    E --> P[Partition by entity key]
    P --> X[Deterministic transform version]
    X --> U[Conditional target upsert or delete]
    U --> CK[Checkpoint after durable commit]
    X --> Q[Quarantine unsupported schema]
```

### Cách đọc diagram

Row hoặc tombstone delete được đóng envelope gồm key/source position, partition theo entity, transform version xác định rồi conditional upsert/delete. Checkpoint đi sau durable commit; schema không hỗ trợ được quarantine. Tombstone phải được giữ semantics để replay snapshot không hồi sinh dữ liệu đã xóa.

## Go Service Implementation

Go source readers stream bounded rows/batches, không load whole table; target workers fixed concurrency, DB acquire deadlines và retries theo SQLSTATE. Queue bound theo bytes lẫn count, reserve CDC lane; pause intake khi target chậm. HTTP control requests dùng request ctx, long migration có persisted state/service ownership riêng. Cancellation pause tạo checkpoint rồi join; shutdown đóng readers/rows/Tx đúng order, không ack uncommitted batch. Kafka clients pin version, handle rebalance ownership và commit contiguous progress.

## Scaling

Parallel snapshot chia key ranges với bounded chunks, không OFFSET pagination qua billions rows. CDC priority để WAL/log retention không bị vượt; per-key workers preserve order hoặc target compare source version. Source/target pool budgets riêng, batch sizes theo bytes/time và transaction WAL pressure. Kafka partitions phân đều keys, nhưng hot key/table cần strategy riêng; thêm workers không chữa target IO bottleneck.

```mermaid
flowchart LR
    S[Source snapshot ranges] --> R1[Range reader A]
    S --> R2[Range reader B]
    R1 --> K1[Kafka partitions]
    R2 --> K1
    C[CDC stream] --> K2[Reserved CDC partitions or lane]
    K1 --> W1[Snapshot worker budget]
    K2 --> W2[CDC worker budget]
    W1 --> T[Target write capacity]
    W2 --> T
```

### Cách đọc diagram

Snapshot ranges chia cho readers và snapshot worker budget; CDC có lane/budget riêng để không bị backfill chiếm hết. Hai nhóm cùng đổ vào target write capacity nên tổng phải được throttle. Các lane không tự đảm bảo merge order; version/checkpoint protocol của design giữ trách nhiệm đó.

## Failure Modes

Snapshot cũ overwrite CDC, missed deletes, source log retention exhausted, target commit ambiguous, duplicates after crash, cross-table order sai, schema change giữa run, transformation nondeterministic, hot partition, DLQ backlog và checksum giả do canonicalization khác.

## Những đường lỗi cần hiểu

Thử crash/network loss tại từng durable boundary ở request flow; kiểm tra invariant sau recovery, không chỉ việc service khởi động lại. Checkpoint chỉ advance sau durable target effect. Crash sau write trước offset/checkpoint tạo replay; upsert/version guard và dedup giữ idempotency. Không commit offset vượt hole khi parallel processing. Schema incompatible dừng affected stream/quarantine có alert; không silently skip rồi tuyên bố migration complete.

```mermaid
flowchart TD
    F[Worker crash or target timeout] --> R[Restart from durable checkpoint]
    R --> E[Replay same event identity]
    E --> V{Target version newer or equal}
    V -->|yes| N[No-op verified duplicate]
    V -->|no| A[Apply deterministic transformation]
    A --> C[Commit target and progress]
    N --> C
    C --> M[Verify counts checksums and gaps]
```

### Cách đọc diagram

Crash/target timeout khởi động lại từ durable checkpoint và replay cùng event ID. Target đã có version mới hơn/bằng thì no-op theo policy xác minh; version chưa áp dụng thì transform deterministic rồi commit state/progress. Cuối cùng kiểm tra counts/checksums/gaps. Một timeout trước đó không chứng minh batch chưa commit, vì thế replay phải idempotent.

## Observability

Progress theo rows/bytes và estimated remaining time, source_position lag theo wall time, WAL/CDC retention headroom, target throughput/lock/IO, per-partition oldest age, checkpoint age, retries/DLQ by schema/error, verification mismatches và worker memory.

## Lần theo bằng chứng khi có sự cố

Progress theo rows/bytes và estimated remaining time, source_position lag theo wall time, WAL/CDC retention headroom, target throughput/lock/IO, per-partition oldest age, checkpoint age, retries/DLQ by schema/error, verification mismatches và worker memory. Tách offered, accepted và completed rates; chọn dependency/queue đầu tiên lệch baseline. Thu profile đúng triệu chứng, đối chiếu trace với durable state theo operation ID. Sau mitigation kiểm tra cả SLO và backlog/reconciliation để tránh tuyên bố phục hồi quá sớm.

## Security

Read-only source credential trừ CDC privileges tối thiểu; scoped target writer, encrypted transit/staging, tenant/table authorization, redact row payloads, audit cutover approval và retention/delete staging sau acceptance.

## Đánh đổi

| Option | Best for | Weakness |
|---|---|---|
| Snapshot then CDC replay | Ordering dễ chứng minh | Lớn CDC backlog/retention |
| Interleaved snapshot and CDC | Catch-up sớm | Version/watermark protocol khó |
| Bigger batches | Amortize commit overhead | Memory, locks, replay cost |
| Per-key ordering | Parallel scalable | Không tự giữ cross-table Tx atomicity |

## Evolution

Pilot một table10M rows với inserts/updates/deletes đồng thời, crash/rebalance tests và end-to-end checksums. Scale100M để đo source/target/WAL bottleneck; dry run full-size estimates với storage retention. Cutover chỉ khi snapshot complete, CDC caught up tới agreed boundary, DLQ resolved, verification approved; freeze/redirect writes theo plan rồi continue reconcile. Rollback sau target nhận writes cần reverse replication hoặc write reconciliation, không chỉ đổi DNS.

## Thực hành, debugging và kết luận

Test crash trước/sau batch commit, checkpoint lost, duplicated/out-of-order changes và delete/tombstone. Target schema transformation cần version và nullable/type policy; counts bằng nhau vẫn có thể chứa dữ liệu sai. Verification dùng partition checksums, sampled semantic comparison và drift/catch-up metrics theo contract.

Cutover chỉ khi lag và verification đạt ngưỡng, writers/readers chuyển theo kế hoạch có rollback hoặc roll-forward rõ. Giữ source authority trong giai đoạn đã chọn; dual writes hai nơi không có protocol tạo divergence. Tăng workers khi target lock/IO bão hòa có thể giảm throughput và đe dọa production source, nên throttle theo health cả hai bên.


## Đọc tiếp

- [capacity-estimation](capacity-estimation.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [Distributed idempotency và ambiguous outcomes](../12-distributed-systems/idempotency.md)
- [Transactional outbox](../12-distributed-systems/outbox-pattern.md)

## Snapshot, checkpoint và verification protocol

1. Ghi migration ID, table schema và transform version bất biến. Source connector phải chứng minh snapshot boundary và change log position có quan hệ đúng theo DB-specific protocol; không tự ghép timestamp wall-clock thành transaction order.
2. Chia key ranges có deterministic boundaries; composite key dùng canonical tuple ordering. Chunk checkpoint lưu last committed source key/position, không dùng số row đã đọc làm vị trí resumable khi source thay đổi.
3. Target apply conditional theo source version chỉ khi version so sánh được trong scope key/partition. Transaction/source position có semantics khác nhau giữa DBs; log rotation/reset/failover cần epoch.
4. Nếu checkpoint cùng target DB, commit applied rows và checkpoint trong một transaction. Nếu checkpoint ở hệ thống khác, effect idempotent rồi checkpoint sau, chấp nhận replay window. Không claim atomicity cross-store khi chưa có protocol.
5. Deletes cần tombstone/version để old replay không resurrect row. DDL/schema changes có barrier hoặc connector schema event được version hóa; transform không gọi external mutable service mà không snapshot/reference version.
6. Verification theo table/range: counts, null/type constraints, key coverage và canonical row hashes theo stable order; aggregate checksums có collision risk nên combine với sampled row-level diff và targeted full diff khi mismatch. Source/target so tại cùng logical boundary, không so hai snapshots khác thời điểm rồi kết luận mất dữ liệu.
7. Cutover checklist có source writes freeze/drain hoặc routing epoch, final CDC boundary reached, outstanding Tx settled, DLQ zero hoặc explicit approved exclusions, replication/backup verified. Ghi rõ ai có thể rollback và dữ liệu target-only sẽ về đâu.

## Failure injection lab

- Kill worker sau target commit nhưng trước offset commit: restart không tạo duplicate business effect.
- Delay snapshot chunk trong khi CDC update/delete cùng key: final target không bị overwrite/resurrect.
- Giảm target throughput xuống5k/s trong 10 phút: source readers backpressure, CDC retention headroom vẫn còn, memory không tăng vô hạn.
- Add nullable column rồi đổi incompatible type: compatible rollout pass, incompatible stream bị quarantine có alert và resumable checkpoint.
- Fail over source và replay boundary: epoch/source position không bị so sánh sai; verification phát hiện gaps.

Đây là design lab, không có migration 5B records được thực thi trong workspace. Để kết luận72h khả thi cần benchmark source snapshot, Kafka retention/network, transform CPU và target write/index/WAL trên dữ liệu đại diện.
