# PostgreSQL replication và CDC — kết quả kiểm chứng

[Mục lục](README.md) · [Thiết kế và runbook](POSTGRESQL_CDC.md) · [Kafka/Redis validation](CLUSTER_VALIDATION.md)

Ngày chạy: **2026-09-30**, Docker trên macOS/ARM64, engine 8 GB RAM/8 CPU. PostgreSQL 16.9, Debezium 3.2.4.Final, Kafka 3.9.1, Redis 7.4.4. Đây là kết quả workload kiểm chứng chức năng, không phải benchmark/SLO.

## Topology và dữ liệu

- Primary: `pg_is_in_recovery()=false`, `wal_level=logical`.
- Replica: `pg_is_in_recovery()=true`, primary ghi nhận application_name `postgres-replica`, state `streaming`, sync_state `async`.
- Hai node có cùng system identifier **7691167656665210913**, cũng trùng với PostgreSQL trước khi đổi topology. Primary giữ nguyên named volume cũ; backup SQL được tạo trước khi dừng writer. Không reset dữ liệu cũ.
- Có physical slot `lab_physical_replica` và bốn logical slots `dbz_vehicle`, `dbz_warranty`, `dbz_inspection`, `dbz_repair`, plugin `pgoutput`, đúng database.
- Bốn publication chứa đúng business table/heartbeat, bốn connector và bốn task RUNNING.
- CDC topics có 3 partitions/RF3/ISR3. Connect config topic 1 partition, offset/status mỗi topic 3; cả ba RF3/ISR3. Worker config thực tế được đối chiếu: JSON converters không schema envelope, producer acks=all/idempotence, storage RF3.

Bằng chứng đầy đủ: [topology, LSN, slots, publications, Connect status và topics](evidence/postgres-cdc/final.json). Đây là snapshot theo thời điểm chạy; LSN và offsets tiếp tục tăng.

Output psql trực tiếp: [primary/config/roles/streams](evidence/postgres-cdc/primary-cli.txt), [replica recovery/receive/replay](evidence/postgres-cdc/replica-cli.txt).

## CDC từ WAL và snapshot

| Bài kiểm tra | Kết quả / evidence |
|---|---|
| API POST xe → replica visible → API PATCH → SQL DELETE đúng row demo | Kafka nhận **c → u → d → tombstone**, đúng ID, full before/after và source LSN. [Records thực tế](evidence/postgres-cdc/insert-update-delete.json) |
| Workflow Vehicle → Warranty → Inspection FAIL → Repair | Domain outbox/consumers tiếp tục hoạt động, cả bốn CDC topics có `op=c` tương ứng. [Workflow và CDC records](evidence/postgres-cdc/four-database-workflow.json) |
| Initial snapshot dữ liệu có trước khi connector được tạo | Cả bốn table topics có `op=r`, source snapshot metadata. [Bốn snapshot records](evidence/postgres-cdc/initial-snapshots.json) |

Probe dùng Kafka consumer để quan sát records do Debezium phát. Nó không đọc bảng để tự publish CDC. SQL DELETE trong demo chỉ minh họa row-change stream; chưa có domain event/API delete nghiệp vụ.

## Các failure scenarios đã chạy

| Case | Quan sát được |
|---|---|
| Dừng replica | Primary INSERT/UPDATE/DELETE vẫn được CDC capture; eventual GET HTTP 200 và `X-Read-Source=primary-fallback`; không còn physical receiver trong pg_stat_replication. [Evidence](evidence/postgres-cdc/replica-down.json) |
| Restart replica | Standby trở lại streaming, không promote; đọc được dữ liệu mới |
| Dừng Debezium, ghi c/u/d, start lại | Nhận đủ **c/u/d/tombstone**, không có `op=r` cho row đã xóa; đọc từ Kafka offsets đã lưu trước outage. [Recovery records](evidence/postgres-cdc/connect-resumed.json) |
| Slot khi Connect down | Logical slots inactive, WAL vẫn được giữ qua restart_lsn. [SQL output](evidence/postgres-cdc/connect-down-slots.txt) |
| Dừng primary | POST trả **503**, readiness degraded; eventual GET row đã replay trả **200** từ replica; replica vẫn recovery=true, wal receiver mất kết nối. [Evidence](evidence/postgres-cdc/primary-down.json) |
| Start primary | Replica reconnect, bốn logical slots active; kiểm lại CRUD CDC và domain workflow thành công |
| Pause replica replay | Default GET row mới trả **200** từ primary; eventual GET trả **404**, byte lag quan sát **11.152 bytes**; CDC vẫn nhận INSERT. [Lag evidence](evidence/postgres-cdc/lag.json) |
| Resume replay | Cùng row đọc được từ replica. [Recovered read](evidence/postgres-cdc/lag-recovered.json) |

Khi primary down trong lượt này, Connect REST vẫn báo RUNNING trong khi task đang retry kết nối. **RUNNING không chứng minh CDC đang tiến triển**; cần kiểm source LSN, slot progress, log và event end-to-end. Lab không có failover manager và không promote replica khi primary dừng.

## Khởi động từ volume trống

Đã tạm dừng stack chính để giữ trong giới hạn RAM, chạy `docker compose up --build -d --wait` trong project riêng `vehicle-platform-db-smoke` với volumes mới, subnet và host ports riêng. Không chạy manual SQL tạo role/slot/publication/connector. Toàn bộ init jobs hoàn tất; verify topology, workflow bốn database và CRUD CDC đều pass: [fresh topology](evidence/postgres-cdc/fresh-verify.json), [fresh workflow](evidence/postgres-cdc/fresh-workflow.json), [fresh CRUD](evidence/postgres-cdc/fresh-cdc.json).

Project tạm đã được dọn cùng các volumes do phép thử tạo; stack chính khởi động lại với volumes/dữ liệu cũ. Cùng scripts đã được chạy trên cả database có dữ liệu lẫn database mới.

Lượt khởi động lại cũng phát hiện Compose `up --wait` có thể coi init job cuối đã exit 0 là container không còn chạy. Đã khai báo Kafka UI chờ `debezium-init` bằng `service_completed_successfully`; chạy lại `up --wait` thành công. Sau phục hồi, PostgreSQL/CDC và Kafka/Redis verifier đều pass, Repair còn một instance.

## Tests và kiểm tra chất lượng

**35 tests pass:** Vehicle 5, Warranty 3, Inspection 2, Repair 2, root 23 (unit 7 + integration 16). Ba integration tests mới kiểm topology/slots/Connect/topics, replica read-only và cache bypass, CDC c/u/d với before image và tombstone.

Ruff pass cho shared code, bốn service, scripts và tests. 33 sơ đồ Mermaid/SVG được render; 53 shell examples và 8 JSON examples qua syntax check. Các bài cũ tiếp tục dùng PostgreSQL/Kafka/Redis thật. Fault drills chạy riêng, không chạy đồng thời với bộ tests. Script có trap phục hồi stopped containers và resume WAL replay khi lỗi.

## Phạm vi và giới hạn

Chưa kiểm thử automatic PostgreSQL promotion, mất host/disk, slot mất hiệu lực do hết WAL, backup restore/PITR, network partition, Connect multi-worker rebalance, schema evolution hoặc load/soak. `max_slot_wal_keep_size` được cấu hình/giải thích nhưng bài lab không cố ý đẩy disk tới giới hạn để phá slot. Recovery đã kiểm chứng khi WAL/slots/offsets còn đầy đủ.

Raw logs/JSON nằm tại `artifacts/postgres-cdc/verified/`. Probe để lại dữ liệu nghiệp vụ mẫu và CDC tombstones; chỉ xóa các vehicle mới tạo cho bài DELETE. Mật khẩu và SQL backup không đưa vào evidence docs.
