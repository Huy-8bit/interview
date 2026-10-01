# Apache Kafka Learning Lab

Lab Kafka chạy local bằng Docker Compose: **cluster 3 node KRaft (Kafka 4.3.1)**, các service **Go (franz-go)** cho một hệ thống e-commerce, traffic generator, Kafka UI, Prometheus + Grafana, Schema Registry. Có **20 lab có kịch bản tự kiểm chứng**, 10 failure scenario, performance lab, và bộ docs đi từ cơ bản tới internals / production / system design.

Mọi con số trong docs và README của lab đều lấy từ **lần chạy thật** trên máy xây dựng lab (laptop, Docker Desktop 8 CPU / 8 GB). Máy của bạn sẽ ra số khác; hãy so sánh tương đối.

---

## Architecture

```text
             HTTP POST /orders                         Kafka cluster (KRaft, RF=3, min ISR=2)
 client ───────────────► producer-service ──┐   ┌───────────────────────────────────────────────┐
 traffic-generator (constant/burst/skewed) ─┼──►│ kafka-1 (.11)  kafka-2 (.12)  kafka-3 (.13)    │
                                            │   │ broker+controller each, JMX exporter :7071     │
                                            │   └───────────────────────────────────────────────┘
          orders (6p) ──┬─► order-consumer-1/2/3  (order-processing-group, manual commit, retry->DLQ)
                        │        └─► inventory-events ; retry-orders ─► orders-dlq
                        ├─► payment-consumer (payment-group) ─► payments (6p) ─┐
                        ├─► analytics-consumer (analytics-group, auto commit, batch) ─► analytics-events (12p)
                        └─► notification-consumer (notification-group) ◄────────┘ ─► notifications ; retry-payments ─► payments-dlq
          txn-input ─► txn-processor (transactions, read_committed) ─► txn-output
          user-events / user-profile-compacted (PUT/DELETE /users/{id}/profile)

 lag-exporter (Admin API) ─► Prometheus ◄─ broker JMX, Go /metrics ─► Grafana (6 dashboards)
 Kafka UI (kafbat) · Schema Registry · Redis (idempotency store) · toolbox (kcli + tc/iptables)
```
Chi tiết & quyết định thiết kế: [docs/02-cluster-architecture.md](docs/02-cluster-architecture.md).

## Requirements

- Docker Desktop / Docker Engine với Compose v2, cấp cho Docker **≥ 6 GB RAM**, ~5 GB disk.
- Không cần cài Kafka hay Go trên host (Go chỉ cần nếu muốn chạy `kcli` từ host).
- Cổng trống trên `127.0.0.1`: 9092-9094, 7071-7073, 8000, 8001, 8011-8018, 8022-8025, 8030, 8080, 8081, 9090, 3000, 6380.

## How to start

```bash
cp .env.example .env            # (Makefile tự làm nếu thiếu)
docker compose up -d --build    # hoặc: make up
docker compose ps               # mọi service (healthy), kafka-init Exited (0)
./scripts/cluster-health.sh     # 53 check thật: broker, quorum, topic, ISR, leader, group, UI, Prometheus
```
Lần đầu build ~2–3 phút. Dừng: `make down` (giữ dữ liệu) · xoá sạch: `make clean`.

## Services & ports

| Service | Host port | Ghi chú |
|---|---|---|
| kafka-1 / kafka-2 / kafka-3 | 9092 / 9093 / 9094 | EXTERNAL listener cho client trên host. Trong docker: `kafka-N:29092` |
| JMX exporter | 7071 / 7072 / 7073 | `/metrics` của từng broker |
| Kafka UI | **8080** | brokers, topics, partitions, leader, replicas, ISR, messages, consumer groups, lag, configs, schemas |
| Grafana | **3000** | admin/admin (anonymous viewer bật) |
| Prometheus | 9090 | targets, alerts |
| Schema Registry | 8081 | |
| producer-service | 8000 | `POST /orders`, `/orders/{id}/events`, `/orders/bulk`, `/raw`, `PUT/DELETE /users/{id}/profile`, `GET /config` |
| traffic-generator | 8001 | `POST /start?mode=constant|burst|skewed-key&rate=..&duration=..`, `/stop`, `GET /status` |
| order-consumer-1..3 (consumer-service-1..3) | 8011-8013 | `/health`, `/metrics`, `/admin/state`, `POST /admin/delay?ms=`, `POST /admin/log-every?n=` |
| order-consumer-4..8 (profile `scale`) | 8014-8018 | `docker compose --profile scale up -d` |
| analytics / notification / txn-processor / payment | 8022 / 8023 / 8024 / 8025 | |
| lag-exporter | 8030 | `kafka_consumergroup_lag`, ISR/leader metrics |
| Redis | 6380 | `docker compose exec redis redis-cli` |

## Topics ([kafka/topics/topics.conf](kafka/topics/topics.conf))

| Topic | P | RF | Config đáng chú ý |
|---|---|---|---|
| orders, payments | 6 | 3 | min ISR 2, 7 ngày |
| analytics-events | 12 | 3 | 3 ngày |
| notifications | 3 | 3 | |
| user-events, inventory-events | 6 | 3 | |
| retry-orders, retry-payments | 3 | 3 | 14 ngày |
| orders-dlq, payments-dlq | 3 | 3 | 30 ngày |
| user-profile-compacted | 3 | 3 | `cleanup.policy=compact`, segment.ms 15s (lab) |
| retention-demo | 1 | 3 | retention.ms 60s, segment.ms 10s (lab) |
| ordering-demo, txn-input, txn-output | 6/3/3 | 3 | lab |

Lý do chọn số partition: [docs/04-topic-partition.md](docs/04-topic-partition.md). Tạo/áp lại: `./scripts/create-topics.sh`.

## How to produce

```bash
curl -s -XPOST localhost:8000/orders -d '{"user_id":1001,"product_id":500,"quantity":2}'
curl -s -XPOST 'localhost:8000/orders?mode=async&acks=1&key=user_id' -d '{"user_id":1001,"product_id":500,"quantity":2}'
curl -s -XPOST 'localhost:8000/orders/order-100/events?count=3'                    # 3 event cùng key
./scripts/produce-test-message.sh                                                  # wrapper
docker compose exec toolbox kcli produce -topic orders -key k1 -value hello -count 5
./scripts/traffic.sh burst 100 120s 10000 10s                                      # 10k msg/s trong 10s, mỗi 30s
# từ host bằng client bất kỳ: bootstrap localhost:9092,localhost:9093,localhost:9094
```

## How to consume / inspect

```bash
./scripts/consume-test-message.sh orders 10 -headers
./scripts/describe-topics.sh orders          # Topic / Partition / Leader / Replicas / ISR
./scripts/describe-consumer-groups.sh        # members, assignment, committed offset, lag
./scripts/consumer-lag.sh order-processing-group --watch
./scripts/partition-stats.sh orders          # records per partition + skew
docker compose logs -f order-consumer-1      # consumer=.. group=.. topic=.. partition=.. offset=.. key=..
```
`kcli` (Go CLI trong toolbox): `docker compose exec toolbox kcli help` — topics, brokers (kèm KRaft quorum), stats, hash, produce, order, consume, group, groups, ordering-test, bench-produce, bench-consume, idempotence-test, dlq-inspect, dlq-replay, large-message, sr-produce.

## Kafka UI & Grafana

- Kafka UI http://localhost:8080 → cluster `kafka-lab`.
- Grafana http://localhost:3000 → folder *Kafka Lab*: Kafka Cluster Overview (home), Producer Performance, Consumer Performance, Consumer Lag, Broker Health, Partition / Replication Health.
- Prometheus http://localhost:9090/alerts.

## Labs

| Lab | Chủ đề |
|---|---|
| [01_producer_consumer](labs/01_producer_consumer) | theo dấu 1 message |
| [02_partitions](labs/02_partitions) | partition, replica, file trên disk |
| [03_message_key](labs/03_message_key) | murmur2(key) % N, sticky partitioner |
| [04_ordering](labs/04_ordering) | ordering trong partition |
| [05_consumer_group](labs/05_consumer_group) | assignment, 8 consumer/6 partition, nhiều group |
| [06_rebalancing](labs/06_rebalancing) | graceful vs crash, eager vs cooperative vs KIP-848 |
| [07_offsets](labs/07_offsets) | LEO/HW/committed/lag, replay, `__consumer_offsets` |
| [08_delivery_semantics](labs/08_delivery_semantics) | duplicate & loss với crash thật, idempotent consumer |
| [09_retry_dlq](labs/09_retry_dlq) | poison, retry ×3, DLQ, replay |
| [10_replication](labs/10_replication) | ISR, min ISR, acks, mất quorum KRaft |
| [11_broker_failure](labs/11_broker_failure) | kill -9 leader dưới tải, election, catch-up |
| [12_hot_partition](labs/12_hot_partition) | hot key |
| [13_retention](labs/13_retention) | segment deletion |
| [14_compaction](labs/14_compaction) | compaction, tombstone |
| [15_transactions](labs/15_transactions) | EOS, read_committed, markers |
| [16_idempotent_producer](labs/16_idempotent_producer) | duplicate do retry, PID/sequence |
| [17_backpressure](labs/17_backpressure) | 5000 msg/s vs consumer chậm |
| [18_large_messages](labs/18_large_messages) | giới hạn kích thước, chunking |
| [19_schema_evolution](labs/19_schema_evolution) | Schema Registry compatibility |
| [20_observability](labs/20_observability) | metrics, dashboards, alerts |
| [performance](labs/performance) | partitions, acks, batching, compression, consumer scaling |
| [failures](labs/failures) | 10 failure scenarios |

```bash
make lab L=04_ordering        # = ./labs/04_ordering/run.sh ; in [OK]/[FAIL] EXPECT và LAB PASSED
./labs/run-all.sh             # mọi lab + reset giữa các lab (~60 phút), in bảng PASS/FAIL
```

## How to reset

```bash
make reset          # ./scripts/reset-lab.sh: start lại broker, gỡ tc/iptables, dừng consumer scale, env mặc định,
                    # delay=0, traffic 5 msg/s, xoá topic tạm & group lab, re-apply topic configs,
                    # purge retry/DLQ, xoá subject SR của lab, flush Redis, chờ ISR đầy
make reset-hard     # docker compose down -v && up --build (xoá mọi dữ liệu)
```

## Learning path

Bắt đầu ở [docs/00-learning-path.md](docs/00-learning-path.md) (18 phase: đọc gì, chạy lab nào, nhìn metric nào, kết quả mong đợi, câu hỏi tự kiểm tra).

| Docs | |
|---|---|
| [00 learning path](docs/00-learning-path.md) | [14 delivery semantics](docs/14-delivery-semantics.md) |
| [01 overview](docs/01-kafka-overview.md) | [15 idempotence](docs/15-idempotence.md) |
| [02 cluster architecture](docs/02-cluster-architecture.md) | [16 transactions](docs/16-transactions.md) |
| [03 KRaft](docs/03-kraft.md) | [17 retry / DLQ](docs/17-retry-dlq.md) |
| [04 topic & partition](docs/04-topic-partition.md) | [18 retention & compaction](docs/18-retention-compaction.md) |
| [05 producer](docs/05-producer.md) | [19 performance](docs/19-performance.md) |
| [06 consumer](docs/06-consumer.md) | [20 monitoring](docs/20-monitoring.md) |
| [07 consumer group](docs/07-consumer-group.md) | [21 production troubleshooting](docs/21-production-troubleshooting.md) |
| [08 offset](docs/08-offset.md) | [22 system design](docs/22-system-design.md) |
| [09 rebalancing](docs/09-rebalancing.md) | [23 schema evolution](docs/23-schema-evolution.md) |
| [10 ordering](docs/10-ordering.md) | [24 security](docs/24-security.md) |
| [11 replication & HW](docs/11-replication.md) | [25 large messages](docs/25-large-messages.md) |
| [12 ISR](docs/12-isr.md) | [26 `__consumer_offsets`](docs/26-consumer-offsets-internals.md) |
| [13 leader election](docs/13-leader-election.md) | [27 log storage](docs/27-log-storage.md) |

## Project structure

```text
docker-compose.yml  .env.example  Makefile  Dockerfile (all Go services)  go.mod
kafka/          Dockerfile (apache/kafka + JMX exporter), config/jmx-exporter.yml, config/kt, topics/topics.conf
pkg/            config, logging, metrics (+HTTP /health /metrics), events, kafka (producer opts, consumer Runner,
                retry/DLQ headers), store (Redis idempotency), app (signals, admin routes)
services/       producer, order-consumer, payment-consumer, analytics-consumer, notification-consumer,
                traffic-generator, txn-processor, lag-exporter
tools/kcli/     lab CLI
scripts/        create/describe/list topics, consumer groups, lag, stop/start broker, produce/consume,
                replay-dlq, traffic, partition-stats, net-fault, cluster-health, reset-lab
monitoring/     prometheus (scrape + alerts), grafana (provisioning, dashboards, dashgen.py)
labs/           01..20, performance, failures, run-all.sh
docs/           00..27
```

## Ghi chú vận hành

- Kafka CLI trong container: dùng wrapper `kt` (bỏ javaagent/heap của broker), vd `docker compose exec kafka-1 kt kafka-topics --bootstrap-server kafka-1:29092 --list`.
- Broker có IP tĩnh 172.30.30.11-13 (lý do: [docs/21 §16](docs/21-production-troubleshooting.md)).
- Lab đặt một vài tham số broker ngắn hơn mặc định để quan sát nhanh: `replica.lag.time.max.ms=10000`, `log.retention.check.interval.ms=10000`, `leader.imbalance.check.interval.seconds=30`.
