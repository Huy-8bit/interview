# 02 — Kiến trúc cluster của lab (Docker Compose, listeners, network)

> Lab: [labs/02_partitions](../labs/02_partitions) · Script: `./scripts/cluster-health.sh`

## WHAT — có gì trong `docker compose up -d --build`

```text
                                   host (macOS / Linux)
   localhost:9092 ─┐  localhost:9093 ─┐  localhost:9094 ─┐      :8080 Kafka UI  :3000 Grafana  :9090 Prometheus
                   │                  │                  │      :8081 Schema Registry  :6380 Redis
┌──────────────────┼──────────────────┼──────────────────┼───────── docker network kafka-lab 172.30.30.0/24 ─┐
│   ┌──────────────▼───┐  ┌───────────▼──────┐  ┌────────▼─────────┐                                       │
│   │ kafka-1 .11      │  │ kafka-2 .12      │  │ kafka-3 .13      │   mỗi node = broker + KRaft controller│
│   │ EXTERNAL :9092   │  │ EXTERNAL :9092   │  │ EXTERNAL :9092   │   (process.roles=broker,controller)    │
│   │ INTERNAL :29092  │◄─┤ INTERNAL :29092  │◄─┤ INTERNAL :29092  │   replication + client trong docker    │
│   │ CONTROLLER:29093 │◄─┤ CONTROLLER:29093 │◄─┤ CONTROLLER:29093 │   Raft (metadata quorum)               │
│   │ JMX exp. :7071   │  │ JMX exp. :7071   │  │ JMX exp. :7071   │                                       │
│   └──────────────────┘  └──────────────────┘  └──────────────────┘                                       │
│        ▲  ▲  ▲                                                                                            │
│  kafka-init (one-shot: tạo topic từ kafka/topics/topics.conf rồi exit 0)                                  │
│                                                                                                           │
│  Go services (cùng image kafka-lab/app:local, mỗi service chạy 1 binary):                                 │
│   producer-service :8000   traffic-generator :8001                                                        │
│   order-consumer-1/2/3 :8011-8013 (group order-processing-group, + retry stage group ...-retry)           │
│   order-consumer-4..8 (profile "scale")                                                                   │
│   payment-consumer :8025   analytics-consumer :8022   notification-consumer :8023   txn-processor :8024   │
│   lag-exporter :8030 (Admin API -> lag, ISR, leader metrics)   toolbox (kcli + tc/iptables)               │
│  Observability: prometheus, grafana, kafka-ui (kafbat), schema-registry, redis (idempotency store)        │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## WHY — các quyết định thiết kế (decision log)

| Quyết định | Lý do | Trade-off |
|---|---|---|
| Kafka **4.3.1**, KRaft, không ZooKeeper | Kafka 4.x đã bỏ ZooKeeper hoàn toàn; KRaft là kiến trúc hiện tại | Một số tài liệu cũ (ZK) không còn đúng |
| **Combined mode** (mỗi node vừa broker vừa controller) | 3 container là đủ để học; vẫn có quorum 3 voter | Production nên tách controller (crash/GC của broker không ảnh hưởng quorum). Lab 10 cho thấy mất 2 node = mất cả broker lẫn quorum |
| Image `apache/kafka` chính thức + JMX exporter agent | Image chính chủ, cấu hình bằng env `KAFKA_*` | Phải tự thêm agent (Dockerfile trong `kafka/`) |
| **franz-go** cho mọi service Go | Pure Go (không cgo/librdkafka), hỗ trợ đầy đủ: idempotence, transactions (GroupTransactSession), cooperative-sticky, KIP-848, admin API (kadm) | Tên config khác Java client (doc map lại) |
| **kafbat/kafka-ui** | Fork đang được maintain của provectus kafka-ui; hiển thị broker/partition/ISR/consumer lag/messages/SR | — |
| lag-exporter tự viết (kadm) thay vì kafka-exporter | kafka-exporter dùng sarama và một số version API cũ; tự viết cho thấy lag được tính thế nào | Thêm một service |
| Redis | Store chung cho idempotent consumer + side effect quan sát được | Production nên dùng chính DB nghiệp vụ, dedup cùng transaction |
| **Static IP cho broker** (172.30.30.11-13) | Lab 10 phát hiện: restart container làm Docker đổi/hoán đổi IP; một broker giữ địa chỉ cũ của peer không thể theo kịp quorum → 118 partition under-replicated kéo dài | Phải khai báo subnet cố định |
| `replica.lag.time.max.ms=10000`, `log.retention.check.interval.ms=10000`, `leader.imbalance.check.interval.seconds=30` | Rút ngắn thời gian quan sát trong lab | Production để mặc định (30000 / 300000 / 300) |

## HOW — listeners: phần dễ cấu hình sai nhất

Kafka client làm 2 bước:

1. Kết nối tới **seed broker** (bootstrap) → gửi `MetadataRequest`.
2. Metadata trả về **advertised listener** của *mọi* broker + leader của từng partition → client **kết nối trực tiếp** tới leader.

=> Địa chỉ trong metadata phải **reachable từ phía client**. Container thấy `kafka-1`, host thấy `localhost:9092`. Vì vậy cần nhiều listener:

```properties
# kafka-2 (env KAFKA_* trong docker-compose.yml)
listeners=INTERNAL://:29092,CONTROLLER://:29093,EXTERNAL://:9092          # bind trong container
advertised.listeners=INTERNAL://kafka-2:29092,EXTERNAL://localhost:9093    # địa chỉ trả về cho client
listener.security.protocol.map=CONTROLLER:PLAINTEXT,INTERNAL:PLAINTEXT,EXTERNAL:PLAINTEXT
inter.broker.listener.name=INTERNAL       # replication đi listener nào
controller.listener.names=CONTROLLER      # Raft đi listener nào (không advertise cho client)
# ports: "127.0.0.1:9093:9092"  -> host 9093 -> container 9092 (EXTERNAL)
```

Listener được chọn **theo listener mà client đã kết nối vào**: client vào cổng 9092 của container (EXTERNAL) sẽ nhận metadata EXTERNAL (`localhost:909x`); client vào 29092 (INTERNAL) nhận `kafka-N:29092`. Verified thực tế:

```text
# từ HOST (KAFKA_BROKERS=localhost:9092,...)        # từ toolbox (KAFKA_BROKERS=kafka-1:29092,...)
NODE  ADVERTISED ENDPOINT                           NODE  ADVERTISED ENDPOINT
1     localhost:9092                                1     kafka-1:29092
2     localhost:9093                                2     kafka-2:29092
3     localhost:9094                                3     kafka-3:29092
```

### Lỗi kinh điển

| Triệu chứng | Nguyên nhân |
|---|---|
| Host client bootstrap được nhưng produce treo / "connection refused kafka-1:29092" | Chỉ có 1 listener advertise hostname nội bộ docker → host không resolve `kafka-1` |
| Container client nhận `localhost:9092` rồi tự kết nối vào chính nó | Advertise `localhost` cho listener mà container dùng |
| Broker không replicate được | `inter.broker.listener.name` trỏ tới listener không reachable giữa broker |
| Cả 3 broker map cùng container port nhưng advertise cùng host port | Client nhảy sai broker → NOT_LEADER_OR_FOLLOWER liên tục |

## INTERNAL — một broker container chạy những gì

- `KafkaRaftServer` với 2 vai trò: `BrokerServer` (ReplicaManager, GroupCoordinator, TransactionCoordinator, SocketServer, LogManager) và `ControllerServer` (QuorumController, RaftManager).
- JVM agent `jmx_prometheus_javaagent` expose `:7071/metrics` (rules ở `kafka/config/jmx-exporter.yml`).
- Data: volume `kafka-N-data` → `/var/lib/kafka/data` chứa cả partition log (`orders-0/`, ...) và metadata log `__cluster_metadata-0/`.

## FAILURE BEHAVIOR (đã quan sát trong lab)

- Restart cả 3 broker cùng lúc: client franz-go log `connection refused` rồi tự reconnect, group rejoin, xử lý tiếp (không cần restart service).
- IP container đổi sau restart (trước khi có static IP): quorum không hồi phục cho tới khi restart lại broker bị kẹt.

## PRODUCTION

- Dùng DNS ổn định (StatefulSet headless service trên K8s, hoặc IP/hostname cố định).
- Tách listener cho client nội bộ / client ngoài / replication / controller; bật TLS/SASL (xem [24-security](24-security.md)).
- `rack` (`broker.rack`) để rải replica qua AZ; consumer có thể đọc follower cùng rack (KIP-392).

## DEBUG

```bash
docker compose exec toolbox kcli brokers                       # endpoint được advertise + quorum
KAFKA_BROKERS=localhost:9092 go run ./tools/kcli brokers       # từ host (cần Go) -> phải thấy localhost:909x
docker compose exec kafka-1 kt kafka-broker-api-versions --bootstrap-server kafka-2:29092 | head
```

## INTERVIEW

1. `listeners` khác `advertised.listeners`? (bind address vs địa chỉ trả về trong metadata)
2. Tại sao client chỉ cần một vài bootstrap server? (metadata trả về toàn bộ broker)
3. Vì sao chạy Kafka trong Docker hay bị lỗi "client không kết nối được"? (advertised listener không reachable)
4. Combined mode có rủi ro gì? (broker overload/GC ảnh hưởng quorum; mất 2/3 node mất cả hai vai trò)
