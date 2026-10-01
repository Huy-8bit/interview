# 22 — System Design: E-commerce event-driven platform trên Kafka

Doc này dùng lab làm "bản thu nhỏ" và mở rộng lên quy mô production. Mọi quyết định đều kèm lý do và đánh đổi — đó là thứ người phỏng vấn muốn nghe.

## 1. Yêu cầu

**Functional**: tạo đơn hàng; thanh toán; giữ tồn kho; gửi thông báo; analytics gần real-time; cập nhật hồ sơ người dùng.
**Non-functional (giả định)**: peak 50 000 event/s (toàn hệ), event trung bình 2 KB; không mất đơn hàng/thanh toán; thứ tự theo đơn hàng; p99 end-to-end < 2s cho payment, < 1 phút cho analytics; replay được 7 ngày; chịu được mất 1 AZ.

## 2. Kiến trúc

```text
                  ┌──────────────┐
  Clients ──────► │ API Gateway  │  auth, rate limit, idempotency-key header
                  └──────┬───────┘
                         ▼
                  ┌──────────────┐  DB transaction: INSERT order + INSERT outbox
                  │ Order Service│──────────────┐
                  └──────────────┘              ▼
                                      ┌─────────────────┐  CDC/relay (Debezium / poller)
                                      │ outbox table    │──────────────┐
                                      └─────────────────┘              ▼
 ┌──────────────────────────────────── Kafka (3 AZ, RF=3, min ISR=2) ─────────────────────────────────────┐
 │  orders (key=order_id)   payments (key=order_id)   inventory-events (key=product_id)                   │
 │  user-events (key=user_id)  user-profile (compacted)  notifications  analytics-events                   │
 │  <group>.retry / <group>.dlq per consumer group                                                         │
 └──────┬──────────────────┬───────────────────────┬───────────────────────┬──────────────────────────────┘
        ▼                  ▼                       ▼                       ▼
 Payment Service     Inventory Service      Notification Service     Analytics (stream processing
 (payment-group)     (inventory-group)      (notification-group)      / Flink / Kafka Streams -> OLAP)
   │ idempotency key      │ dedup event_id         │ dedup event_id
   ▼                      ▼                        ▼
 PSP API               Inventory DB             Email/SMS provider
   └─► payments topic (PaymentSucceeded/Failed) ─► Order Service cập nhật trạng thái (saga)
```

Ánh xạ sang lab: producer-service ≈ Order Service (không có outbox), order-consumer ≈ Inventory, payment-consumer ≈ Payment (idempotency key với gateway giả), notification-consumer, analytics-consumer, txn-processor (EOS trong Kafka).

## 3. Topic design

| Topic | Key | Partitions | Retention / policy | Ghi chú |
|---|---|---|---|---|
| `orders` | order_id | 48 (xem §5) | delete, 7 ngày | event OrderCreated/Updated/Cancelled |
| `payments` | order_id | 48 | delete, 30 ngày (đối soát) | cùng key với orders → co-partition cho join |
| `inventory-events` | product_id | 24 | delete, 7 ngày | coi chừng hot product (flash sale) |
| `user-events` | user_id | 24 | delete, 30 ngày | lịch sử |
| `user-profile` | user_id | 12 | **compact** | state hiện tại, tombstone khi xoá tài khoản (GDPR) |
| `notifications` | user_id | 12 | delete, 3 ngày | |
| `<group>.retry`, `<group>.dlq` | giữ key gốc | 6 | 14 / 30 ngày | riêng từng consumer group |

Quy ước: tên `domain.entity.event-version` (vd `ecommerce.orders.v1`) hoặc như lab; một topic một loại thực thể (nhiều event type) để giữ thứ tự giữa các event của cùng đơn hàng.

## 4. Message key & ordering

- Cần thứ tự: các event của **một đơn hàng** (Created → Paid → Shipped) → key = `order_id`.
- Không cần thứ tự toàn cục, không cần thứ tự giữa các đơn của một user (nếu cần → key = user_id, nhưng whale user = hot partition).
- Producer idempotent + acks=all → không đảo thứ tự khi retry.
- Retry topic phá thứ tự → với payments dùng **blocking retry** hoặc **park theo key** (lab: payment-consumer inline retry rồi stop-the-line).
- Consumer xử lý event có `version/sequence`; bỏ qua event cũ hơn state.

## 5. Partition count (cách suy nghĩ)

```text
orders: peak 20 000 msg/s (phần của 50k), 2 KB  -> 40 MB/s
Producer: 1 partition chịu ~10 MB/s an toàn (đo bằng benchmark thật) -> ≥ 4
Consumer: Payment xử lý 8 ms/record (gọi PSP)  -> 125 msg/s/partition/consumer -> 20 000/125 = 160 (!)
   -> không tăng partition tới 160: xử lý song song trong consumer theo key (key-hash worker pool, 16 worker)
      -> 125 × 16 = 2 000 msg/s/partition -> ≥ 10 partition
Parallelism mong muốn: 24 instance trong 3 AZ ; tăng trưởng 2× trong 2 năm
=> chọn 48 (bội số của 3 broker/AZ, dư cho 2 năm, không phải repartition).
```
Nguyên tắc: tính từ **consumer** (thường là nút cổ chai), nhân hệ số tăng trưởng, kiểm tra giới hạn partition/broker (vài nghìn replica/broker là thoải mái với KRaft), tránh tăng partition sau này với topic cần ordering.

## 6. Replication & durability

- RF=3, `min.insync.replicas=2`, `acks=all`, `enable.idempotence=true`, `unclean.leader.election.enable=false`.
- `broker.rack` = AZ → mỗi partition có 1 replica / AZ → mất 1 AZ vẫn đọc ghi được (lab 10: mất 1 broker vẫn ghi; mất 2 → NOT_ENOUGH_REPLICAS).
- KRaft: 3 (hoặc 5) dedicated controllers, mỗi AZ một.
- Consumer đọc follower cùng AZ (KIP-392) để giảm chi phí cross-AZ.

## 7. Consumer groups

| Group | Commit | Semantics | Idempotency |
|---|---|---|---|
| payment-group | manual sau khi lưu kết quả | at-least-once | idempotency key = order_id tới PSP; bảng payments unique(order_id) |
| inventory-group | manual | at-least-once | dedup event_id trong cùng DB transaction với reserve |
| notification-group | manual | at-least-once | dedup event_id (không gửi email 2 lần) |
| analytics | auto / EOS (Flink checkpoint) | tolerates dup hoặc EOS | — |
| order-status-updater (đọc payments) | manual | at-least-once | state machine idempotent |

Cooperative-sticky hoặc KIP-848; static membership cho stateful consumer; graceful shutdown.

## 8. Idempotency & exactly-once

- **Producer**: outbox pattern — event được ghi cùng DB transaction với đơn hàng → không có "đơn hàng có nhưng event mất" hoặc ngược lại. Relay at-least-once + event_id cố định → consumer dedup.
- **Consumer**: mọi side effect idempotent (event_id dedup / idempotency key / upsert theo version).
- Kafka transactions chỉ cho luồng Kafka → Kafka (stream processing analytics, enrich).
- Exactly-once không bao trùm PSP / email (lab 14/15/08).

## 9. Retry & DLQ

- Phân loại lỗi transient / permanent; transient: inline vài lần (ms) → retry topic có backoff (5s, 1m, 10m) → DLQ.
- Permanent (schema, validation): DLQ ngay.
- Downstream sập toàn bộ: **pause** consumer / circuit breaker, không xả cả triệu record vào DLQ.
- DLQ có alert, dashboard, công cụ replay (lab `kcli dlq-replay`), replay vào retry topic của chính group.

## 10. Schema evolution

- Schema Registry (Avro/Protobuf), subject theo topic, compatibility **BACKWARD** (mặc định) hoặc **FULL** cho topic dùng chung nhiều team.
- Quy tắc: thêm field phải có default; không đổi kiểu; không xoá field bắt buộc; đổi breaking → topic mới `v2` + chạy song song.
- CI kiểm tra compatibility trước deploy (lab 19 dùng REST `/compatibility`).

## 11. Observability

- Metrics: cluster (URP, offline, active controller, ISR shrink), producer (rate, error, latency), consumer (lag, **e2e latency**, processing time, retry/DLQ, rebalance).
- Tracing: propagate `traceparent` qua record headers.
- Log có `topic/partition/offset/key/event_id`.
- SLO: "99% payment event xử lý trong 2s" → alert theo burn rate của e2e latency.

## 12. Capacity planning (ví dụ tính)

Giả định: **50 000 event/s**, **2 KB/event**, RF=3, retention 7 ngày, nén zstd tỉ lệ ~4 (lab đo 5.4 với JSON thật — dùng số thận trọng hơn), 4 consumer group đọc mọi thứ.

```text
Raw ingress           = 50 000 × 2 KB              = 100 MB/s        (~0.8 Gbit/s)
Sau nén (÷4)          = 25 MB/s vào leader
Replication traffic   = 25 MB/s × (RF−1)=2         = 50 MB/s giữa các broker (cross-AZ: tính tiền!)
Ghi disk toàn cluster = 25 MB/s × RF 3             = 75 MB/s
Consumer egress       = 25 MB/s × 4 group          = 100 MB/s
Network in tổng       = 25 (producer) + 50 (replication) = 75 MB/s
Network out tổng      = 100 (consumer) + 50 (replication) = 150 MB/s

Storage/ngày (1 bản)  = 25 MB/s × 86 400 s         = 2.16 TB/ngày
×RF 3                 = 6.48 TB/ngày
7 ngày retention      = 45.4 TB
+ headroom 40% (không chạy disk > 60–70%, chỗ cho reassign/burst) = ~64 TB tổng
Nếu không nén: 100 MB/s × 86 400 × 3 × 7 = 181 TB (+40% ≈ 254 TB)
```
Công thức tổng quát:
```text
ingress = msg_rate × avg_size / compression_ratio
storage = ingress × retention_seconds × RF / target_disk_utilization
replication_bw = ingress × (RF − 1)
egress = ingress × (consumer_groups + RF − 1)
brokers ≥ max( storage / disk_per_broker , network / nic_per_broker × 0.6 , partitions / partitions_per_broker )
```
Ví dụ: broker 12 TB disk → 64/12 ≈ 6 broker; NIC 10 Gbit (~1.2 GB/s) dư sức → chọn 6 broker (2/AZ), sau đó benchmark thật. Không dùng một con số cố định cho mọi hệ thống.

## 13. Backpressure & scaling

- Kafka hấp thụ burst (lab 17: lag 137k rồi drain). Đảm bảo retention > thời gian drain xấu nhất.
- Scale consumer theo **lag + e2e latency** (KEDA), tối đa = số partition.
- Producer: buffer đầy → Produce block → API trả 503/429 (đừng nuốt lỗi).
- Quotas (`producer_byte_rate`, `consumer_byte_rate`) để một tenant không làm nghẽn cluster.

## 14. Failure handling (tóm tắt)

| Failure | Thiết kế xử lý |
|---|---|
| Broker / AZ chết | RF3 rack-aware, min ISR 2, clients retry; failover ~ session timeout (lab: 6–9s) |
| Controller | quorum 3/5 dedicated |
| Consumer crash | at-least-once + idempotent; session timeout hợp lý; DLQ cho poison |
| Downstream chết | circuit breaker + pause; retry topic có backoff |
| Producer service crash | outbox → không mất event |
| Hot key (flash sale) | key tổ hợp / salting + aggregator; topic riêng cho sản phẩm hot |
| Schema sai | registry + compatibility + DLQ |
| Lỗi do con người (xoá topic, config sai) | IaC cho topic, ACL, review; backup bằng MirrorMaker 2 / tiered storage |

## 15. Disaster recovery & multi-region

| Mô hình | Cách làm | RPO / RTO | Đánh đổi |
|---|---|---|---|
| Stretched cluster 3 AZ (một region) | một cluster, rack awareness | RPO 0 trong region | không chống mất cả region |
| Active-passive (MirrorMaker 2 / Cluster Linking) | replicate async sang region B | RPO giây–phút | offset khác nhau giữa cluster (MM2 checkpoint/offset sync), failover phải dời consumer |
| Active-active | mỗi region có topic local + mirror topic của region kia (`us.orders`, `eu.orders`) | — | xung đột dữ liệu, ordering toàn cục không có, cần idempotency xuyên vùng |
| Stretched across 3 regions | latency cao cho acks=all | RPO 0 | chi phí latency mỗi ghi |

Kiểm tra DR định kỳ (game day): tắt region, đo RTO thật.

## 16. Security

TLS mọi listener (cả inter-broker & controller), SASL/SCRAM hoặc mTLS/OAUTHBEARER, ACL theo nguyên tắc tối thiểu (service chỉ WRITE topic của mình, READ topic cần đọc + group của mình), mã hoá disk, PII: không đưa dữ liệu nhạy cảm vào key; tombstone cho xoá theo GDPR với topic compacted; topic event dài hạn: crypto-shredding. Chi tiết [24-security](24-security.md).

## 17. Câu hỏi phỏng vấn system design thường gặp

1. Thiết kế đảm bảo "đơn hàng tạo xong thì chắc chắn có event" → outbox.
2. Payment không bị trừ tiền 2 lần → idempotency key + at-least-once.
3. Flash sale 1 sản phẩm → hot partition → chiến lược key.
4. Tính số partition/broker/disk cho X msg/s → công thức §5, §12.
5. Mất một region → MM2/Cluster Linking, offset translation.
6. Thay đổi schema không làm vỡ consumer cũ → registry + BACKWARD/FULL.
