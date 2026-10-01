# 01 — Kafka là gì: mental model

> Lab đi kèm: [labs/01_producer_consumer](../labs/01_producer_consumer), [labs/02_partitions](../labs/02_partitions)

## WHAT

Apache Kafka là một **distributed, partitioned, replicated commit log**. Nói cho đúng bản chất:

- **Log**: một dãy record *chỉ được append* (không update, không delete từng record), mỗi record có một **offset** tăng dần.
- **Partitioned**: một topic được chia thành nhiều log độc lập (partition). Mỗi partition là một đơn vị thứ tự, đơn vị song song, đơn vị replication.
- **Replicated**: mỗi partition có N bản sao (replica) trên N broker khác nhau. Một replica là **leader** (nhận ghi + phục vụ đọc), các replica còn lại là **follower** (kéo dữ liệu từ leader).
- **Distributed**: các partition/replica rải trên nhiều broker; metadata (ai là leader, ISR là gì, topic nào tồn tại) được quản lý bởi **KRaft controller quorum** (Kafka 4.x không còn ZooKeeper).

Kafka **không phải** message queue kiểu RabbitMQ: consumer đọc xong **không xoá** message. Dữ liệu ở lại tới khi hết retention (thời gian/kích thước) hoặc bị compaction. Nhiều nhóm consumer độc lập đọc cùng một dữ liệu, mỗi nhóm tự nhớ vị trí (offset) của mình.

```text
                       topic "orders" (6 partitions, RF=3)
   P0: [0][1][2][3][4][5][6]...  leader kafka-1, follower kafka-2, kafka-3
   P1: [0][1][2][3]...           leader kafka-2, follower kafka-3, kafka-1
   ...
   P5: [0][1][2]...              leader kafka-3, follower kafka-1, kafka-2

   order-processing-group  ── committed offset P0=4086, P1=4169 ...
   payment-group           ── committed offset P0=4100, P1=4170 ...   (độc lập!)
```

## WHY — vì sao hệ thống event-driven dùng Kafka

| Nhu cầu | Kafka giải quyết thế nào |
|---|---|
| Tách producer khỏi consumer (decoupling) | Producer chỉ biết topic; consumer đến/đi tuỳ ý, không cần producer biết |
| Chịu tải đột biến (burst) | Log trên disk là buffer: producer ghi 5000 msg/s, consumer xử lý 430 msg/s → lag tăng chứ không mất (lab 17) |
| Nhiều hệ thống cùng cần một sự kiện | Mỗi consumer group đọc toàn bộ stream độc lập (lab 05) |
| Replay / reprocess | Dữ liệu còn trong log → reset offset và đọc lại (lab 07) |
| Thứ tự theo thực thể | Cùng key → cùng partition → có thứ tự (lab 03, 04) |
| Durability | RF=3, `acks=all`, `min.insync.replicas=2` (lab 10, 11) |
| Throughput cao | Ghi tuần tự + batching + compression + zero-copy sendfile + page cache |

## HOW — một message đi qua Kafka như thế nào (end-to-end)

```text
Application
    │  POST /orders  (producer-service)
    ▼
Producer (franz-go)
    ├── serialize (JSON)                     -> value bytes, key = order_id
    ├── determine partition                  -> murmur2(key) % 6  (lab 03: order-lab03 -> P0)
    ├── append vào batch của partition đó    -> RecordBatch trong bộ nhớ client
    ├── chờ linger.ms hoặc batch đầy
    ├── compress batch (lz4)
    ▼
ProduceRequest ──────────────► Partition Leader (vd kafka-1)
                                   ├── validate (CRC, size, producerId/sequence nếu idempotent)
                                   ├── append vào active segment (*.log) + cập nhật index
                                   │       (ghi vào page cache, KHÔNG fsync mỗi record)
                                   ├── followers gửi FetchRequest kéo dữ liệu
                                   ├── khi mọi replica trong ISR có offset → HW tăng
                                   ▼
                              ProduceResponse (acks=all: chỉ sau khi ISR có record)
    ▼
Producer nhận ack (partition, offset) -> trả HTTP 201 {"partition":5,"offset":518}

Consumer (order-consumer-2, group order-processing-group)
    ├── FetchRequest(partition 5, offset 518) gửi tới LEADER của P5
    ▼
Leader trả về các batch có offset < High Watermark (chỉ dữ liệu đã replicate đủ)
    ▼
Consumer
    ├── decompress + deserialize
    ├── process (Redis side effect, produce inventory-events)
    ├── commit offset 519 (= offset record tiếp theo cần đọc)
    ▼
OffsetCommitRequest -> Group Coordinator -> ghi vào topic nội bộ __consumer_offsets
```

Lab 01 cho thấy đúng chuỗi này với dữ liệu thật:

```text
producer-service  produced topic=orders partition=5 offset=518 key=order-1edb61a132ae acks=all latency=17.396ms
order-consumer-2  processed group=order-processing-group topic=orders partition=5 offset=518 key=order-1edb61a132ae hw=519 lag=0
payment-consumer  processed group=payment-group          topic=orders partition=5 offset=518 ...
```

## INTERNAL BEHAVIOR — vài điều "tại sao Kafka nhanh"

1. **Sequential I/O**: chỉ append vào cuối file segment, đọc tuần tự. Disk (kể cả HDD) đọc/ghi tuần tự rất nhanh.
2. **Page cache**: Kafka không tự cache trong heap; ghi vào OS page cache, consumer đọc dữ liệu "nóng" thẳng từ RAM. Đó là lý do broker chỉ cần heap nhỏ (lab dùng `-Xmx512m`) còn RAM còn lại để OS cache.
3. **Zero-copy** (`sendfile`): broker gửi bytes từ page cache ra socket mà không copy qua user space (với PLAINTEXT; TLS làm mất zero-copy).
4. **Batching end-to-end**: producer gửi batch, broker lưu nguyên batch (không giải nén nếu codec giống), consumer nhận nguyên batch. Lab performance: linger=0/16KB → 67k rec/s, linger=20ms/1MB → 336k rec/s.
5. **Không có ack per message ở consumer**: consumer chỉ commit "đã xử lý tới offset X" → rẻ hơn rất nhiều so với ack từng message.

## FAILURE BEHAVIOR (tóm tắt — chi tiết ở các doc sau)

| Sự cố | Kafka làm gì | Lab |
|---|---|---|
| Broker leader chết | Controller fence broker sau `broker.session.timeout.ms` (9s), bầu leader mới từ ISR | 11 (leader đổi trong 6–9s, 11956/11956 record an toàn) |
| Follower chậm | Leader loại follower khỏi ISR sau `replica.lag.time.max.ms` | failures/replica_out_of_sync |
| Consumer chết | Coordinator chờ `session.timeout.ms` rồi rebalance | 06 (10.6s) |
| Consumer crash trước commit | Record được giao lại → duplicate | 08 |
| Mất 2/3 node KRaft | Mất quorum metadata: không bầu leader, ISR không đổi, `acks=all` timeout | 10 |

## TRADE-OFF

- Kafka cho **ordering trong partition**, không global ordering.
- Kafka cho **at-least-once** dễ dàng; exactly-once chỉ trong phạm vi Kafka (transactions), side effect ngoài Kafka phải tự idempotent.
- Kafka là **pull-based**: consumer kiểm soát tốc độ (backpressure tự nhiên), đổi lại latency phụ thuộc poll/fetch.
- Retention dài = replay được nhưng tốn disk (xem capacity planning ở [22-system-design](22-system-design.md)).

## PRODUCTION

- Luôn: RF=3, `min.insync.replicas=2`, `acks=all`, `enable.idempotence=true`, `unclean.leader.election.enable=false` cho dữ liệu quan trọng.
- Tắt `auto.create.topics.enable` (lab tắt) — topic phải được thiết kế (partition count, retention, cleanup.policy).
- Tách controller ra node riêng (dedicated controllers) cho cluster lớn; lab dùng combined mode cho gọn.

## DEBUG — bắt đầu từ đâu

```bash
./scripts/cluster-health.sh                     # 53 checks: broker, quorum, topic, ISR, group, UI
./scripts/describe-topics.sh orders             # leader / replicas / ISR
./scripts/consumer-lag.sh order-processing-group
docker compose logs -f order-consumer-1         # log có topic/partition/offset/key/group
```

## INTERVIEW

1. Kafka khác RabbitMQ thế nào? (log vs queue, consumer giữ offset, replay, retention, pull vs push, ordering per partition)
2. Vì sao Kafka nhanh dù ghi xuống disk? (sequential I/O, page cache, zero-copy, batching, compression)
3. Một message được coi là "committed" khi nào? (khi mọi replica trong ISR đã có → HW vượt qua offset đó; consumer chỉ thấy dữ liệu dưới HW)
4. Partition là đơn vị của những gì? (ordering, parallelism, replication, storage)
5. Consumer group khác consumer instance thế nào? (group = một "ứng dụng", mỗi group nhận toàn bộ stream; instance trong group chia partition)
