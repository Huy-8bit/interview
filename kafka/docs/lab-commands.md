# Thứ tự lệnh chạy lab (CLI runbook)

Chạy **từ trên xuống dưới**. Mọi lệnh chạy trong thư mục gốc của lab:

```bash
cd ~/Desktop/poc/lab/kafka
```

Quy ước:
- Trước mỗi lab: đọc `labs/<lab>/README.md` và doc tương ứng (ghi ở cột "Đọc").
- Mỗi lab in `[OK] EXPECT ...` / `[FAIL] EXPECT ...` và kết thúc bằng `LAB PASSED`.
- **Sau mỗi lab chạy `./scripts/reset-lab.sh`** để lab sau không bị ảnh hưởng (broker bị dừng, network fault, consumer crash, config tạm…).
- Nếu một lab bị ngắt giữa chừng (Ctrl-C), chạy `./scripts/reset-lab.sh` rồi chạy lại lab đó.

---

## Bước 0 — Khởi động (một lần)

```bash
cp .env.example .env                 # có thể bỏ qua: make up tự tạo
docker compose up -d --build         # lần đầu ~2–3 phút
docker compose ps                    # mọi service (healthy), kafka-init: Exited (0)
./scripts/cluster-health.sh          # phải thấy: cluster-health: 53 checks passed
```

Mở trên trình duyệt:
- Kafka UI: http://localhost:8080
- Grafana: http://localhost:3000 (admin / admin)
- Prometheus: http://localhost:9090

---

## Bước 1 — Làm quen cluster

```bash
docker compose exec toolbox kcli brokers           # 3 broker, active controller KRaft, lag từng voter
./scripts/list-topics.sh                           # danh sách topic
./scripts/describe-topics.sh orders                # Topic / Partition / Leader / Replicas / ISR
./scripts/describe-consumer-groups.sh              # group, member, partition được giao, lag
./scripts/partition-stats.sh orders                # số record mỗi partition
docker compose logs -f order-consumer-1            # log consumer (Ctrl-C để thoát)
```

---

## Bước 2 — Các lab theo thứ tự học

| # | Lệnh | Đọc | Thời gian |
|---|---|---|---|
| 1 | `./labs/01_producer_consumer/run.sh` | docs 01, 05, 06 | ~10s |
| 2 | `./labs/02_partitions/run.sh` | docs 04, 27 | ~10s |
| 3 | `./labs/03_message_key/run.sh` | doc 04 | ~10s |
| 4 | `./labs/04_ordering/run.sh` | doc 10 | ~10s |
| 5 | `./labs/05_consumer_group/run.sh` | doc 07 | ~1.5 phút |
| 6 | `./labs/07_offsets/run.sh` | docs 08, 26 | ~1.5 phút |
| 7 | `./labs/10_replication/run.sh` | docs 11, 12, 03 | ~2 phút |
| 8 | `./labs/11_broker_failure/run.sh` | doc 13 | ~1.5 phút |
| 9 | `./labs/08_delivery_semantics/run.sh` | doc 14 | ~2 phút |
| 10 | `./labs/16_idempotent_producer/run.sh` | doc 15 | ~30s |
| 11 | `./labs/09_retry_dlq/run.sh` | doc 17 | ~1 phút |
| 12 | `./labs/06_rebalancing/run.sh` | doc 09 | ~5 phút |
| 13 | `./labs/13_retention/run.sh` | doc 18 | ~1.5 phút |
| 14 | `./labs/14_compaction/run.sh` | doc 18 | ~1.5 phút |
| 15 | `./labs/15_transactions/run.sh` | doc 16 | ~30s |
| 16 | `./labs/performance/run.sh` | doc 19 | ~4 phút |
| 17 | `./labs/17_backpressure/run.sh` | doc 19 | ~2 phút |
| 18 | `./labs/12_hot_partition/run.sh` | docs 19, 21 | ~1 phút |
| 19 | `./labs/18_large_messages/run.sh` | doc 25 | ~30s |
| 20 | `./labs/20_observability/run.sh` | doc 20 | ~10s |
| 21 | `./labs/19_schema_evolution/run.sh` | doc 23 | ~10s |

Chạy lần lượt, mỗi lab kèm reset:

```bash
./labs/01_producer_consumer/run.sh    && ./scripts/reset-lab.sh
./labs/02_partitions/run.sh           && ./scripts/reset-lab.sh
./labs/03_message_key/run.sh          && ./scripts/reset-lab.sh
./labs/04_ordering/run.sh             && ./scripts/reset-lab.sh
./labs/05_consumer_group/run.sh       && ./scripts/reset-lab.sh
./labs/07_offsets/run.sh              && ./scripts/reset-lab.sh
./labs/10_replication/run.sh          && ./scripts/reset-lab.sh
./labs/11_broker_failure/run.sh       && ./scripts/reset-lab.sh
./labs/08_delivery_semantics/run.sh   && ./scripts/reset-lab.sh
./labs/16_idempotent_producer/run.sh  && ./scripts/reset-lab.sh
./labs/09_retry_dlq/run.sh            && ./scripts/reset-lab.sh
./labs/06_rebalancing/run.sh          && ./scripts/reset-lab.sh
./labs/13_retention/run.sh            && ./scripts/reset-lab.sh
./labs/14_compaction/run.sh           && ./scripts/reset-lab.sh
./labs/15_transactions/run.sh         && ./scripts/reset-lab.sh
./labs/performance/run.sh             && ./scripts/reset-lab.sh
./labs/17_backpressure/run.sh         && ./scripts/reset-lab.sh
./labs/12_hot_partition/run.sh        && ./scripts/reset-lab.sh
./labs/18_large_messages/run.sh       && ./scripts/reset-lab.sh
./labs/20_observability/run.sh
./labs/19_schema_evolution/run.sh     && ./scripts/reset-lab.sh
```

Mẹo: với lab 11 và 17, mở Grafana (dashboard *Partition / Replication Health*, *Producer Performance*, *Consumer Lag*) trong lúc chạy để thấy leader đổi, ISR co/giãn, lag tăng/giảm.

Chạy riêng một phần của lab 06: `PARTS="A B" ./labs/06_rebalancing/run.sh` (A = rời group sạch, B = crash).

---

## Bước 3 — Failure scenarios

```bash
./labs/failures/broker_failure/run.sh       && ./scripts/reset-lab.sh   # controlled shutdown dưới tải
./labs/failures/replica_out_of_sync/run.sh  && ./scripts/reset-lab.sh   # follower bị loại khỏi ISR
./labs/failures/network_delay/run.sh        && ./scripts/reset-lab.sh   # tc netem 200ms
./labs/failures/producer_restart/run.sh     && ./scripts/reset-lab.sh   # SIGTERM vs SIGKILL producer
```

Các thư mục còn lại trong `labs/failures/` (leader_failure, consumer_crash, slow_consumer, poison_message, consumer_rebalance, hot_partition) gọi lại lab 11, 06+08, 17, 09, 06, 12 — đã chạy ở Bước 2.

---

## Bước 4 — Đọc tổng kết

- [21-production-troubleshooting.md](21-production-troubleshooting.md)
- [22-system-design.md](22-system-design.md)
- [24-security.md](24-security.md)

---

## Lệnh tự thí nghiệm (dùng bất cứ lúc nào)

```bash
# Produce
curl -s -XPOST localhost:8000/orders -d '{"user_id":1001,"product_id":500,"quantity":2}'
curl -s -XPOST 'localhost:8000/orders?mode=async&acks=1&key=user_id' -d '{"user_id":1001,"product_id":500,"quantity":2}'
curl -s -XPOST 'localhost:8000/orders/order-100/events?count=5'      # 5 event cùng key
./scripts/produce-test-message.sh

# Consume / xem dữ liệu
./scripts/consume-test-message.sh orders 10 -headers
docker compose exec toolbox kcli consume -topic orders -partition 0 -from start -max 5

# Lag
./scripts/consumer-lag.sh                                            # tổng lag mỗi group
./scripts/consumer-lag.sh order-processing-group --watch             # Ctrl-C để thoát

# Traffic
./scripts/traffic.sh status
./scripts/traffic.sh constant 1000 60s
./scripts/traffic.sh burst 100 120s 10000 10s
./scripts/traffic.sh skewed 2000 60s 0.8
./scripts/traffic.sh default                                         # về 5 msg/s

# Broker
./scripts/stop-broker.sh 1                                           # thêm --kill để mô phỏng crash
./scripts/start-broker.sh 1

# Consumer (runtime)
curl -s localhost:8011/admin/state
curl -s -XPOST 'localhost:8011/admin/delay?ms=50'                    # giả lập xử lý chậm
docker compose --profile scale up -d                                 # thêm order-consumer-4..8

# DLQ
./scripts/replay-dlq.sh orders-dlq --dry-run
./scripts/replay-dlq.sh orders-dlq

# Network fault
./scripts/net-fault.sh delay 3 300ms
./scripts/net-fault.sh block-replication 3
./scripts/net-fault.sh clear 3

# kcli
docker compose exec toolbox kcli help
docker compose exec toolbox kcli hash -partitions 6 order-100 user-1001

# Kafka CLI gốc (dùng wrapper kt trong container broker)
docker compose exec kafka-1 kt kafka-topics --bootstrap-server kafka-1:29092 --describe --topic orders
docker compose exec kafka-1 kt kafka-consumer-groups --bootstrap-server kafka-1:29092 --describe --all-groups
docker compose exec kafka-1 kt kafka-metadata-quorum --bootstrap-server kafka-1:29092 describe --status
```

---

## Chạy toàn bộ một lượt (kiểm tra hồi quy)

```bash
./labs/run-all.sh                          # mọi lab + reset giữa các lab, in bảng PASS/FAIL (~30–60 phút)
./labs/run-all.sh 04_ordering 09_retry_dlq # chỉ vài lab
```

Log từng lab: `/tmp/kafka-lab-runs/<lab>.log`.

---

## Dừng / dọn dẹp

```bash
./scripts/reset-lab.sh        # về trạng thái sạch, giữ dữ liệu
make down                     # dừng toàn bộ container, giữ dữ liệu
docker compose up -d          # bật lại
make clean                    # dừng và XOÁ toàn bộ dữ liệu (volumes)
make reset-hard               # xoá sạch rồi dựng lại từ đầu
```

## Khi có lỗi

```bash
./scripts/cluster-health.sh                       # check nào FAIL?
docker compose ps                                  # service nào không healthy?
docker compose logs --tail 50 <service>
./scripts/reset-lab.sh                             # đa số trường hợp là đủ
```
