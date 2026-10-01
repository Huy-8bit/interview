# 00 — Learning path (18 phase)

Danh sách lệnh theo đúng thứ tự: [lab-commands.md](lab-commands.md).

Mỗi phase: **đọc** → **chạy lab** → **quan sát** → **expected** → **tự trả lời**. Sau mỗi lab: `make reset` (hoặc `./scripts/reset-lab.sh`).
Chạy một lab: `make lab L=04_ordering` hoặc `./labs/04_ordering/run.sh`. Mỗi lab in `[OK] EXPECT ...` / `[FAIL]` và kết thúc bằng `LAB PASSED`.

---

### Phase 1 — Kafka mental model
- **Đọc**: [01-kafka-overview](01-kafka-overview.md), [02-cluster-architecture](02-cluster-architecture.md)
- **Lab**: `./scripts/cluster-health.sh`, mở Kafka UI http://localhost:8080 (Brokers, Topics)
- **Quan sát**: 3 broker, controller, 15 topic; Grafana "Kafka Cluster Overview"
- **Expected**: 53 checks passed; leader rải đều 3 broker
- **Tự trả lời**: Kafka khác message queue ở đâu? Vì sao Kafka nhanh dù ghi disk? Listener/advertised listener là gì?

### Phase 2 — Producer / Consumer
- **Đọc**: [05-producer](05-producer.md), [06-consumer](06-consumer.md)
- **Lab**: [01_producer_consumer](../labs/01_producer_consumer)
- **Quan sát**: log producer (`topic partition offset key`) và log consumer cùng offset ở 3 group; `produced_total`, `consumed_total`
- **Expected**: sync trả partition/offset; async trả 202, ack đến sau ở log
- **Tự trả lời**: Consumer fetch từ broker nào? Committed offset là gì? Async produce nguy hiểm ở đâu?

### Phase 3 — Topic / Partition
- **Đọc**: [04-topic-partition](04-topic-partition.md), [27-log-storage](27-log-storage.md)
- **Lab**: [02_partitions](../labs/02_partitions)
- **Quan sát**: thư mục `orders-N` trên mỗi broker, file `.log/.index/.timeindex`, `kafka-dump-log` (producerId, sequence)
- **Expected**: 6 thư mục orders trên mỗi broker; phân phối record ~đều (max/avg ≈ 1.06)
- **Tự trả lời**: Trade-off khi tăng partition? Vì sao không giảm partition được?

### Phase 4 — Message key / Ordering
- **Đọc**: [10-ordering](10-ordering.md)
- **Lab**: [03_message_key](../labs/03_message_key), [04_ordering](../labs/04_ordering)
- **Quan sát**: `kcli hash`, sync vs async null key (2000 batch vs 1 batch), IN ORDER vs OUT OF ORDER
- **Expected**: cùng key → cùng partition; round-robin không key → OUT OF ORDER
- **Tự trả lời**: Kafka đảm bảo ordering ở mức nào? Những gì phá ordering dù đã có key?

### Phase 5 — Consumer group
- **Đọc**: [07-consumer-group](07-consumer-group.md)
- **Lab**: [05_consumer_group](../labs/05_consumer_group)
- **Quan sát**: assignment thật 3 instance, 8 instance (2 IDLE), 1 record → 3 group
- **Expected**: `exactly 2 idle`, `processed once per group`
- **Tự trả lời**: Instance vs group? Max parallelism? Coordinator là ai?

### Phase 6 — Offset / Commit / Lag
- **Đọc**: [08-offset](08-offset.md), [26-consumer-offsets-internals](26-consumer-offsets-internals.md)
- **Lab**: [07_offsets](../labs/07_offsets)
- **Quan sát**: get-offsets earliest/latest, lag tăng khi consumer dừng & giảm khi chạy lại, răng cưa auto-commit, reset-offsets, bản ghi trong `__consumer_offsets`
- **Metric**: Grafana "Consumer Lag"
- **Expected**: lag ≥ 300 khi dừng 10s @50 msg/s, < 100 sau restart; commit record tìm thấy ở đúng partition coordinator
- **Tự trả lời**: Lag tính thế nào? Vì sao lag auto-commit răng cưa? Replay 1 giờ dữ liệu làm sao?

### Phase 7 — Replication / ISR
- **Đọc**: [11-replication](11-replication.md), [12-isr](12-isr.md), [03-kraft](03-kraft.md)
- **Lab**: [10_replication](../labs/10_replication), [failures/replica_out_of_sync](../labs/failures/replica_out_of_sync)
- **Quan sát**: ISR co từ 3 → 2 → 1 (+ ELR), NOT_ENOUGH_REPLICAS, mất quorum (activecontrollercount=0)
- **Metric**: UnderReplicated, UnderMinIsr, IsrShrinks
- **Expected**: mất 1 broker vẫn ghi acks=all; ISR=1 → acks=all bị từ chối, acks=1 vẫn nhận; mất 2 node → không controller
- **Tự trả lời**: HW là gì? Vì sao follower không fetch vẫn có thể trong ISR? min ISR ảnh hưởng acks=1 không?

### Phase 8 — Broker failure / Leader election
- **Đọc**: [13-leader-election](13-leader-election.md)
- **Lab**: [11_broker_failure](../labs/11_broker_failure), [failures/broker_failure](../labs/failures/broker_failure)
- **Quan sát**: leader P0 đổi sau ~9s, epoch tăng, truncation khi broker quay lại, preferred leader trở về
- **Expected**: appended == acked, failed=0
- **Tự trả lời**: Các bước failover? Controlled shutdown khác crash thế nào? Unclean election?

### Phase 9 — Delivery semantics
- **Đọc**: [14-delivery-semantics](14-delivery-semantics.md)
- **Lab**: [08_delivery_semantics](../labs/08_delivery_semantics)
- **Quan sát**: crash sau xử lý → deliveries=2; commit trước → mất; idempotent effect áp dụng 1 lần
- **Expected**: 5 EXPECT pass
- **Tự trả lời**: Vẽ timeline mất / trùng. Exactly-once của Kafka không bao gồm gì?

### Phase 10 — Idempotency
- **Đọc**: [15-idempotence](15-idempotence.md)
- **Lab**: [16_idempotent_producer](../labs/16_idempotent_producer), [failures/producer_restart](../labs/failures/producer_restart)
- **Quan sát**: duplicate khi tắt idempotence dưới network delay; producerId/sequence trong dump-log; PID đổi sau restart
- **Expected**: DUPLICATES>0 khi off, =0 khi on
- **Tự trả lời**: PID/sequence hoạt động thế nào? Vì sao vẫn cần idempotent consumer?

### Phase 11 — Retry / DLQ
- **Đọc**: [17-retry-dlq](17-retry-dlq.md)
- **Lab**: [09_retry_dlq](../labs/09_retry_dlq)
- **Quan sát**: attempt 1/3, 2/3, 3/3 với backoff 2s/4s/8s → DLQ; headers metadata; replay sau khi sửa dependency
- **Metric**: `retry_total`, `dlq_total`
- **Tự trả lời**: Retry topic phá ordering thế nào? Phân loại lỗi? Replay vào đâu?

### Phase 12 — Rebalance
- **Đọc**: [09-rebalancing](09-rebalancing.md)
- **Lab**: [06_rebalancing](../labs/06_rebalancing)
- **Quan sát**: graceful 478ms vs crash 10.6s; eager revoke all vs cooperative; KIP-848
- **Metric**: `rebalance_events_total`, `assigned_partitions`
- **Tự trả lời**: Session timeout vs max.poll.interval? Rebalance storm?

### Phase 13 — Retention / Compaction
- **Đọc**: [18-retention-compaction](18-retention-compaction.md)
- **Lab**: [13_retention](../labs/13_retention), [14_compaction](../labs/14_compaction)
- **Quan sát**: segment bị xoá, log start offset nhảy; chỉ còn v3, tombstone biến mất, offset có lỗ
- **Tự trả lời**: Retention theo segment nghĩa là gì? delete vs compact vs compact,delete?

### Phase 14 — Transactions
- **Đọc**: [16-transactions](16-transactions.md)
- **Lab**: [15_transactions](../labs/15_transactions)
- **Quan sát**: TXN ABORTED/COMMITTED, read_uncommitted 4 vs read_committed 3, control markers, `kafka-transactions describe`
- **Tự trả lời**: transactional.id, epoch, coordinator, LSO?

### Phase 15 — Performance
- **Đọc**: [19-performance](19-performance.md), [25-large-messages](25-large-messages.md)
- **Lab**: [performance](../labs/performance), [17_backpressure](../labs/17_backpressure), [12_hot_partition](../labs/12_hot_partition), [18_large_messages](../labs/18_large_messages)
- **Quan sát**: consumer plateau ở 6, batching ×5, compression ratio, lag 137k, hot partition 83%
- **Tự trả lời**: Tăng throughput producer? Vì sao thêm consumer không giúp?

### Phase 16 — Observability
- **Đọc**: [20-monitoring](20-monitoring.md)
- **Lab**: [20_observability](../labs/20_observability) + mở 6 dashboard trong khi chạy lab 11 và 17
- **Tự trả lời**: 5 metric quan trọng nhất? Produce latency cao thì xem gì?

### Phase 17 — Production troubleshooting
- **Đọc**: [21-production-troubleshooting](21-production-troubleshooting.md), [24-security](24-security.md), [23-schema-evolution](23-schema-evolution.md)
- **Lab**: [failures/*](../labs/failures), [19_schema_evolution](../labs/19_schema_evolution)
- **Tự trả lời**: Với mỗi triệu chứng trong doc 21, bạn mở metric nào trước?

### Phase 18 — Kafka system design
- **Đọc**: [22-system-design](22-system-design.md)
- **Bài tập**: tự thiết kế lại cho 200k event/s, 5 KB, retention 14 ngày, 2 region; tính partition, broker, disk, network bằng công thức §12; so sánh với đáp án của bạn sau 1 tuần.

---

**Chạy toàn bộ**: `./labs/run-all.sh` (~45–60 phút, reset giữa các lab, in bảng PASS/FAIL).
