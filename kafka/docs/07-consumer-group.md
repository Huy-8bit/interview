# 07 — Consumer Group, Group Coordinator & partition assignment

> Lab: [05_consumer_group](../labs/05_consumer_group), [06_rebalancing](../labs/06_rebalancing) · `kcli group`, `./scripts/describe-consumer-groups.sh`

## WHAT

- **Consumer group** (`group.id`) = một *ứng dụng logic* đọc topic. Kafka đảm bảo mỗi partition được giao cho **đúng một member** trong group tại một thời điểm.
- **Nhiều group** đọc cùng topic hoàn toàn độc lập: mỗi group có committed offset riêng → mỗi group nhận *toàn bộ* stream.

```text
                    orders (6 partitions)
        ┌───────────────┬───────────────┬────────────────┐
        ▼               ▼               ▼                ▼
order-processing-group  payment-group  notification-group  analytics-group
 3 instance chia 6 P     1 instance đọc 6 P   1 instance        1 instance
 c1: P0 P4               payment-consumer-1  ...
 c2: P1 P5
 c3: P2 P3
```

Lab 05 bước 4: produce **1** order → được xử lý **1 lần mỗi group** (order-processing-group, payment-group, notification-group — 3 dòng log, cùng `partition=0 offset=856`).

| Instance trong cùng group | Các group khác nhau |
|---|---|
| Chia nhau partition (load balancing) | Mỗi group nhận toàn bộ dữ liệu (fan-out / pub-sub) |
| Thêm instance = tăng song song (tới số partition) | Thêm group = thêm một "ứng dụng" đọc độc lập |
| Chung committed offset | Committed offset riêng |
| Rebalance khi member vào/ra | Không ảnh hưởng nhau |

## Nhiều consumer hơn partition (lab 05 bước 2)

```text
[09:53:03] group=order-processing-group state=Stable assignor=cooperative-sticky members=8
  order-consumer-1  orders[P0]
  order-consumer-2  orders[P1]
  order-consumer-3  orders[P2]
  order-consumer-4  orders[P3]
  order-consumer-5  orders[P5]
  order-consumer-6  (none) <-- IDLE member
  order-consumer-7  (none) <-- IDLE member
  order-consumer-8  orders[P4]
```
Max consumer song song trong một group = số partition. Member dư vẫn heartbeat, là **hot standby** (thay thế ngay khi một member chết) nhưng không tăng throughput (performance E: 6 consumer 2298 rec/s, 8 consumer 2386 rec/s).

## Group Coordinator & classic protocol

Coordinator = leader của partition `__consumer_offsets` mà group băm vào (`abs(groupId.hashCode()) % 50`; lab 07: `lab-07-replay` → partition 21 → leader kafka-2).

```text
Consumer                       Group Coordinator (broker)
   │ FindCoordinator(group) ──────────► (bất kỳ broker) -> "coordinator = kafka-2"
   │ JoinGroup(protocols=[cooperative-sticky], subscription) ─►
   │                                    chờ mọi member join (rebalance timeout / initial delay 3s)
   │◄──────────── JoinGroup response: generation=N, memberId, leader=c1, (leader nhận danh sách member)
   │ [leader] tính assignment bằng assignor phía CLIENT
   │ SyncGroup(assignment cho mọi member) ─►
   │◄──────────── SyncGroup response: partition của tôi
   │ Heartbeat ─────────────────────────► (mỗi heartbeat.interval.ms)
   │◄──────────── OK | REBALANCE_IN_PROGRESS (-> rejoin)
   │ OffsetCommit(generation, memberId, offsets) ─► ghi vào __consumer_offsets
   │ LeaveGroup ─────────────────────────► (shutdown sạch -> rebalance ngay)
```

Trạng thái group: `Empty` → `PreparingRebalance` → `CompletingRebalance` → `Stable` → (`Dead`). Offset commit của member có generation cũ bị từ chối (`ILLEGAL_GENERATION`) → **fencing** zombie consumer.

## KIP-848: "consumer" protocol (Kafka 4.x)

- Một API duy nhất `ConsumerGroupHeartbeat`; **broker** (coordinator) tính assignment (assignor phía server: `uniform`, `range`).
- Không còn "stop-the-world": mỗi member nhận assignment mục tiêu và hội tụ dần (revoke → ack → assign) — incremental theo từng member.
- Lab 06 E chạy group bằng `GROUP_PROTOCOL=consumer` (franz-go `ServerSideBalancer`, Kafka 4.3), `kcli group` hiển thị `protocol=consumer (KIP-848) assignor=range`; nhóm còn **migrate online** classic → consumer → classic trong cùng lab.

## Partition assignment strategies

| Strategy | Cách chia | Rebalance | Ghi chú |
|---|---|---|---|
| **Range** | chia theo dải liên tiếp *mỗi topic* | Eager (revoke tất cả) | Nhiều topic → member đầu nhận nhiều hơn; co-partition các topic cùng số partition |
| **RoundRobin** | xoay vòng toàn bộ partition | Eager | Đều hơn khi nhiều topic |
| **Sticky** | đều + giữ assignment cũ nhiều nhất | Eager (vẫn revoke tất cả rồi trả lại phần lớn) | Ít di chuyển state |
| **Cooperative-sticky** | như sticky | **Incremental** (2 vòng: revoke phần cần chuyển, rồi assign) | Mặc định khuyến nghị cho classic protocol |
| KIP-848 server assignors | `uniform` / `range` (server) | Incremental, không global barrier | Kafka ≥ 4.0 |

Dữ liệu lab 06 (stop order-consumer-2):

```text
EAGER (range):
  order-consumer-1 REBALANCE revoked="orders[P0 P1]" still_owns=(none)      <- mất cả phần của mình
  order-consumer-1 REBALANCE assigned newly_assigned="orders[P0 P1 P2]"
  order-consumer-3 REBALANCE revoked="orders[P4 P5]" still_owns=(none)
  order-consumer-3 REBALANCE assigned newly_assigned="orders[P3 P4 P5]"
COOPERATIVE-STICKY:
  survivors revoked nothing (0 non-empty revokes); chỉ nhận thêm P1 / P4
KIP-848 (range server-side):
  order-consumer-1 revoked=orders[P2] -> assigned orders[P4 P5]  (range không sticky nhưng chuyển từng phần)
```

## Static membership (`group.instance.id`)

Member có id cố định; restart trong `session.timeout.ms` → coordinator trả lại đúng partition cũ **không rebalance**. Dùng cho rolling deploy của consumer có state lớn. Đổi lại: crash thật được phát hiện chậm hơn (phải đợi session timeout), và member static **không** gửi LeaveGroup khi đóng. Runner hỗ trợ qua `STATIC_MEMBERSHIP=true`.

## FAILURE / DEBUG

- "Ghost member": member cũ không rời group sạch (crash, hoặc LeaveGroup mất khi coordinator đang chuyển leader) → group chờ `session.timeout` (45s mặc định) trước khi stabilise. Log coordinator: `Member ... has failed, removing it from the group`.
- Rebalance liên tục: xử lý quá lâu (> max poll / rebalance timeout), GC pause, deploy rolling không static membership, autoscaler bật/tắt member.

```bash
docker compose exec toolbox kcli group -group order-processing-group -watch 2s
docker compose exec toolbox kcli groups
docker compose logs kafka-1 kafka-2 kafka-3 | grep "GroupCoordinator" | grep order-processing-group
```

## INTERVIEW

1. Consumer instance vs consumer group?
2. Ai tính assignment trong classic protocol? Trong KIP-848?
3. Eager vs cooperative rebalance khác nhau ở đâu, ảnh hưởng gì tới latency?
4. 10 partition, group A 3 consumer, group B 12 consumer: mỗi consumer nhận gì?
5. Static membership giải quyết vấn đề gì, đánh đổi gì?
