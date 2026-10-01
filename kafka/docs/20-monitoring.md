# 20 — Monitoring & Observability

> Lab: [20_observability](../labs/20_observability) · Grafana http://localhost:3000 (admin/admin) · Prometheus http://localhost:9090 · Kafka UI http://localhost:8080

## Kiến trúc metrics của lab

```text
kafka-1..3 JVM ── JMX MBeans ── jmx_prometheus_javaagent (:7071) ─┐
lag-exporter (Go, Admin API: lag, ISR, leader, offsets) (:8080) ──┤
Go services /metrics (produced_total, consumed_total, ...) ───────┼──► Prometheus (scrape 5s) ──► Grafana (6 dashboard provisioned)
                                                                  │                         └──► alerts.yml
Kafka UI đọc trực tiếp Admin API + JMX exporter của broker ───────┘
```

## Metric quan trọng

### Broker / cluster (JMX)
| Metric (tên trong lab) | Ý nghĩa | Bình thường |
|---|---|---|
| `kafka_controller_kafkacontroller_activecontrollercount` | 1 trên đúng một node | tổng = 1 |
| `kafka_server_replicamanager_underreplicatedpartitions` | partition (leader trên broker này) có ISR < replicas | 0 |
| `kafka_controller_kafkacontroller_offlinepartitionscount` | partition không có leader | 0 |
| `kafka_server_replicamanager_underminisrpartitioncount` / `atminisrpartitioncount` | dưới / ngay tại min ISR | 0 / 0 |
| `kafka_server_replicamanager_isrshrinks_total` / `isrexpands_total` | ISR co / giãn | ~0 |
| `kafka_server_brokertopicmetrics_messagesin_total{topic}` / `bytesin_total` / `bytesout_total` | throughput | — |
| `kafka_server_brokertopicmetrics_replicationbytesin_total` | băng thông replication | ≈ (RF−1)× bytes in |
| `kafka_network_requestmetrics_requests_total{request}` | request rate theo loại | — |
| `kafka_network_requestmetrics_total_time_ms{request,quantile}`, `remote_time_ms`, `local_time_ms`, `requestqueue_time_ms` | latency phía broker, tách theo giai đoạn | Produce p99 vài ms |
| `kafka_server_kafkarequesthandlerpool_requesthandler_avg_idle_ratio` | I/O thread rảnh | > 0.3 |
| `kafka_network_socketserver_networkprocessoravgidlepercent` | network thread rảnh | > 0.3 |
| `kafka_server_replicafetchermanager_maxlag{clientid="Replica"}` | follower tụt bao nhiêu record | nhỏ |
| `process_cpu_seconds_total`, `jvm_memory_used_bytes`, `jvm_gc_collection_seconds_*` | CPU / heap / GC | — |
| `kafka_log_log_size{topic,partition}` | kích thước log | theo retention |
| `kafka_controller_controllerstats_uncleanleaderelections_total` | unclean election | 0 |

### Consumer lag (lag-exporter, Admin API)
`kafka_consumergroup_lag{group,topic,partition}`, `kafka_consumergroup_lag_sum`, `kafka_consumergroup_committed_offset`, `kafka_consumergroup_members`, `kafka_consumergroup_partition_owner{member}`, `kafka_topic_partition_{current,oldest}_offset`, `kafka_topic_partition_{leader,in_sync_replicas,under_replicated,offline,leader_is_preferred}`.

### Ứng dụng (Go services)
`produced_total`, `produce_error_total{error}`, `produce_latency_seconds`, `consumed_total{group,topic,partition}`, `consume_error_total`, `processing_duration_seconds`, `end_to_end_latency_seconds`, `retry_total`, `dlq_total`, `duplicate_skipped_total`, `rebalance_events_total{event}`, `assigned_partitions`, `offset_commit_total{result}`.

## Dashboards (provision tự động từ `monitoring/grafana/dashboards`, sinh bởi `dashgen.py`)

| Dashboard | Trả lời câu hỏi |
|---|---|
| Kafka Cluster Overview | Cluster có khoẻ không? (brokers up, controller, URP, offline, under min ISR, throughput, lag) |
| Producer Performance | Producer gửi bao nhiêu, lỗi gì, latency client vs broker (total/remote) |
| Consumer Performance | Mỗi instance xử lý bao nhiêu, theo partition, processing/e2e latency, retry/DLQ/duplicate, rebalance, commit |
| Consumer Lag | Lag theo group/partition, tốc độ tăng lag, ai sở hữu partition |
| Broker Health | CPU, heap, GC, thread pool idle, request queue, replication bytes, disk |
| Partition / Replication Health | ISR shrink/expand, URP, leader per broker, leader per partition, elections |

`scripts/internal/check_dashboards.py` chạy *mọi* query của dashboard vào Prometheus và báo query nào không có dữ liệu (lab 20 dùng nó).

## Alerts (monitoring/prometheus/alerts.yml)

KafkaUnderReplicatedPartitions, KafkaOfflinePartitions, KafkaNoActiveController, KafkaBrokerDown, ConsumerLagGrowing (lag > 1000 **và** đang tăng), DLQReceivingMessages. Lab 20 bắt gặp `ConsumerLagGrowing` firing thật — do một group debug bỏ quên với lag 238k → đúng loại "group mồ côi" phải dọn.

## Nguyên tắc

- **USE** cho broker (Utilization, Saturation, Errors), **RED** cho service (Rate, Errors, Duration).
- Alert theo triệu chứng ảnh hưởng người dùng (lag tăng, e2e latency, offline partition), dashboard theo nguyên nhân.
- Lag tuyệt đối dễ đánh lừa (auto-commit sawtooth, topic throughput khác nhau) → kết hợp **tốc độ thay đổi lag** và **thời gian lag** (e2e latency hoặc tuổi record cũ nhất chưa xử lý).
- Log có cấu trúc với `topic partition offset key group consumer` để trace một message cụ thể.

## INTERVIEW
1. 5 metric quan trọng nhất của Kafka broker?
2. Lag lấy ở đâu ra? Vì sao alert theo lag tuyệt đối không đủ?
3. Phân biệt UnderReplicated, UnderMinIsr, Offline.
4. Produce latency cao: nhìn metric nào để biết do local (disk), remote (replication) hay queue (thread pool)?
