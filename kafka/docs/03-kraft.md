# 03 — KRaft: Kafka Raft metadata mode

> Lab: [labs/10_replication](../labs/10_replication) (phần mất quorum), [labs/11_broker_failure](../labs/11_broker_failure) · `kcli brokers`

## WHAT

KRaft thay ZooKeeper bằng một **Raft quorum nội bộ** để quản lý **metadata** của cluster:

- topic/partition nào tồn tại, replica nằm ở đâu
- **partition leader** và **ISR** của từng partition
- broker nào đã đăng ký, broker nào bị **fence**
- config động, ACL, feature flags (metadata.version), producer id block, ...

Toàn bộ metadata là một **log**: topic nội bộ `__cluster_metadata` (1 partition), được replicate bằng Raft giữa các **controller voter**.

```text
           controller quorum (voters 1,2,3 — trong lab chính là kafka-1..3)
  ┌──────────────┐   Raft Fetch    ┌──────────────┐   Raft Fetch   ┌──────────────┐
  │ kafka-1      │◄────────────────│ kafka-2      │───────────────►│ kafka-3      │
  │ follower     │                 │ LEADER       │                │ follower     │
  │ (voter)      │                 │ = ACTIVE     │                │ (voter)      │
  └──────────────┘                 │  CONTROLLER  │                └──────────────┘
                                   └──────┬───────┘
                      metadata log __cluster_metadata (records: TopicRecord, PartitionRecord,
                      PartitionChangeRecord(leader, isr), RegisterBrokerRecord, FenceBrokerRecord ...)
                                          │
         brokers (kể cả chính các node này) FETCH metadata log và áp dụng vào bộ nhớ (MetadataImage)
```

## Hai khái niệm "leader" khác nhau — hay bị nhầm

| | **Active controller** (metadata leader) | **Partition leader** |
|---|---|---|
| Là gì | Leader Raft của `__cluster_metadata` | Replica nhận ghi/đọc của một partition |
| Số lượng | Đúng **1** cho cả cluster | **1 cho mỗi partition** (lab: 175 partition) |
| Bầu thế nào | Raft vote giữa controller voters (cần đa số) | Controller **chọn** từ ISR (hoặc ELR) và ghi `PartitionChangeRecord` |
| Xem ở đâu | `kcli brokers` (DescribeQuorum), metric `activecontrollercount` | `kcli topics`, `kafka-topics --describe` |

Lab ghi nhận: lúc khởi tạo active controller là node 2 (epoch 1); sau một lần stall ~3s của Docker VM, node 2 resign, node 1 thắng epoch 2:

```text
[RaftManager id=2] Did not receive fetch request from the majority of the voters within 3000ms ... -> ResignedState
[RaftManager id=1] Transitioning to Prospective state due to fetch timeout
[RaftManager id=1] Completed transition to Leader(... epoch=2 ...)
```

**Lưu ý thú vị**: trường `controller id` trong `MetadataResponse` ở KRaft **không** phải active controller — broker trả về một broker ngẫu nhiên (client gửi admin request tới đó, broker *forward* sang controller). `kcli brokers` in cả hai để thấy khác biệt; muốn biết controller thật phải dùng `DescribeQuorum`:

```text
metadata 'controller id': 1  (in KRaft this is just a broker that forwards admin requests, NOT the quorum leader)
KRaft metadata quorum (__cluster_metadata): ACTIVE CONTROLLER = node 1, leader epoch 2, high watermark 2262
VOTER  ROLE      LOG END OFFSET  LAG
1      LEADER    2262            0
2      follower  2262            0
3      follower  2262            0
```

## HOW — các luồng chính

### Broker registration & heartbeat
1. Broker khởi động → `BrokerRegistrationRequest` tới active controller → nhận **broker epoch**.
2. Broker gửi `BrokerHeartbeat` định kỳ (`broker.heartbeat.interval.ms`, 2s).
3. Không heartbeat trong `broker.session.timeout.ms` (9s mặc định) → controller ghi `FenceBrokerRecord` → mọi partition do broker đó lead được **bầu leader mới**.
4. Broker shutdown bình thường → **controlled shutdown**: broker xin controller chuyển leader đi trước rồi mới tắt (failures/broker_failure: 7996 acked = 7996 appended, 0 lỗi).

Lab 11 (kill -9 leader): partition `orders P0` vẫn hiển thị leader `kafka-1` ở +3s, +6s; tới +9s đổi sang `kafka-2`, leader epoch 18→19 — đúng khoảng `broker.session.timeout.ms=9s`.

### Leader election (partition)
Controller chọn leader mới = replica còn sống đầu tiên trong danh sách replicas **mà nằm trong ISR** (hoặc ELR — KIP-966), ghi `PartitionChangeRecord(leader, leaderEpoch+1, isr)`; brokers đọc metadata log, broker mới làm leader bắt đầu nhận ghi, follower bắt đầu fetch từ leader mới.

### ISR change
Leader phát hiện follower tụt quá `replica.lag.time.max.ms` → gửi `AlterPartition` tới **controller** → controller ghi record mới. => **ISR chỉ đổi được khi có controller**.

## FAILURE BEHAVIOR — mất quorum (lab 10, phần 3)

3 voter cần **đa số = 2**. Tắt kafka-2 và kafka-3:

```text
ERROR: describe quorum: context deadline exceeded
kafka_controller_kafkacontroller_activecontrollercount 0.0
[RaftManager id=1] ... ProspectiveState(epoch=16 ...)    <- liên tục thử bầu, không đủ phiếu
acks=1   -> produced topic=orders partition=3 offset=6495     <- leader cũ vẫn nhận ghi!
acks=all -> ERROR: records have timed out before they were able to be produced
```

Giải thích:
- Không có active controller → **không bầu leader mới, không thay đổi ISR, không tạo topic**.
- Leader hiện tại (kafka-1) vẫn coi ISR là {1,2,3} (không ai shrink được) → `acks=all` chờ follower đã chết → **timeout**, không phải `NOT_ENOUGH_REPLICAS`.
- `acks=1` vẫn thành công: chỉ 1 bản sao tồn tại → rủi ro mất dữ liệu.

Sau khi start lại 2 node: quorum có đa số, controller mới được bầu, ISR mở rộng lại (kiểm tra bằng `wait_isr_full`).

## PERFORMANCE

- Metadata log nhỏ (lab ~20k record sau vài giờ); controller định kỳ snapshot (`metadata.log.max.record.bytes.between.snapshots`).
- KRaft giúp failover controller nhanh (ms–giây) và hỗ trợ hàng triệu partition tốt hơn ZooKeeper (không phải load toàn bộ state khi đổi controller — state đã có sẵn ở các voter).

## TRADE-OFF

| Combined mode (lab) | Dedicated controllers (production) |
|---|---|
| Ít node | Thêm 3 node nhỏ |
| Broker bận/GC → ảnh hưởng Raft (lab thấy re-election khi VM stall) | Controller cô lập |
| Mất 2 node = mất cả data plane lẫn control plane | Mất broker không ảnh hưởng quorum |

Số voter: 3 (chịu 1 lỗi) hoặc 5 (chịu 2 lỗi). Số chẵn không tăng khả năng chịu lỗi.

## PRODUCTION

- 3 hoặc 5 dedicated controllers, rải qua AZ.
- Dùng `controller.quorum.bootstrap.servers` + dynamic quorum (KIP-853) để thay voter không downtime (lab dùng static `controller.quorum.voters` cho đơn giản).
- Giám sát: `activecontrollercount` (tổng = 1), `kafka_controller_kafkacontroller_newactivecontrollerscount` (tăng = flapping), `lastappliedrecordlagms`, `fencedbrokercount`.
- Địa chỉ ổn định cho controller (bài học static IP).

## DEBUG

```bash
docker compose exec toolbox kcli brokers                            # quorum leader + lag từng voter
docker compose exec kafka-1 kt kafka-metadata-quorum --bootstrap-server kafka-1:29092 describe --status
docker compose exec kafka-1 kt kafka-metadata-quorum --bootstrap-server kafka-1:29092 describe --replication
docker compose logs kafka-1 | grep -E "RaftManager.*transition"     # lịch sử bầu cử
# đọc metadata log (offline):
docker compose exec kafka-1 kt kafka-dump-log --cluster-metadata-decoder --files /var/lib/kafka/data/__cluster_metadata-0/00000000000000000000.log | head
```

## INTERVIEW

1. KRaft thay ZooKeeper ở đâu? Lợi ích? (metadata là log Raft; failover nhanh, scale partition, một hệ thống thay vì hai)
2. Active controller khác partition leader thế nào?
3. Mất 2/3 controller thì producer `acks=all` và `acks=1` thấy gì? Vì sao?
4. Broker bị coi là chết khi nào? (không heartbeat trong `broker.session.timeout.ms` → fenced)
5. Vì sao số controller nên lẻ?
