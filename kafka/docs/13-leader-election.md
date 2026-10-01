# 13 — Leader election (clean, unclean, preferred)

> Lab: [11_broker_failure](../labs/11_broker_failure), [failures/broker_failure](../labs/failures/broker_failure), [failures/leader_failure](../labs/failures/leader_failure)

## WHAT

Ba loại "bầu leader":

1. **KRaft controller election** (Raft vote) — chọn active controller. Xem [03-kraft](03-kraft.md).
2. **Partition leader election** — controller chọn leader mới cho partition khi leader cũ chết / shutdown / reassign.
3. **Preferred leader election** — trả leadership về *preferred replica* (replica đầu tiên trong danh sách) để cân bằng tải.

## HOW — partition leader election khi broker chết

```text
t0      kafka-1 bị kill -9
t0..9s  kafka-1 không heartbeat; leader của P0 vẫn là kafka-1 trong metadata
        producer: lỗi kết nối -> retry ; consumer: fetch lỗi
~9s     controller: broker.session.timeout.ms hết -> FenceBrokerRecord(1)
        với mỗi partition kafka-1 lead: chọn leader mới ∈ ISR \ {1} (ưu tiên thứ tự replicas)
        ghi PartitionChangeRecord(leader=2, leaderEpoch=19, isr=[2,3])
        brokers áp dụng metadata: kafka-2 bắt đầu làm leader P0
        clients refresh metadata -> gửi tới kafka-2
```
Lab 11 (dữ liệu thật): leader đổi giữa +6s và +9s; 11956 record ack = 11956 record trong log; traffic-generator không có record nào thất bại.

Controlled shutdown (SIGTERM): broker xin controller chuyển leadership **trước** khi tắt → gần như không gián đoạn (failures/broker_failure: 7996/7996, failed=0).

## Clean vs Unclean

| | Clean (mặc định) | Unclean (`unclean.leader.election.enable=true`) |
|---|---|---|
| Leader mới được chọn từ | ISR (hoặc ELR) | bất kỳ replica còn sống, kể cả ngoài ISR |
| Khi ISR toàn bộ chết | partition **offline** (không đọc/ghi) cho tới khi replica ISR quay lại | partition online ngay với replica tụt hậu |
| Dữ liệu | không mất dữ liệu đã commit | **mất** các record replica đó chưa có (kể cả đã ack acks=all); offset có thể bị "tái sử dụng" → consumer bối rối |
| Ưu tiên | Consistency | Availability |

Lab giữ `false` (topic orders describe hiện `unclean.leader.election.enable=false`). Metric `uncleanleaderelections_total` = 0. Chỉ bật cho dữ liệu chấp nhận mất (metrics, log) hoặc làm thao tác khẩn cấp có chủ đích (`kafka-leader-election --election-type unclean`).

## Preferred leader

- Replica đầu trong `Replicas: 1,2,3` là preferred. Sau failover, leader dồn về các broker còn sống → mất cân bằng (lab sau quorum loss: `leaders per broker: kafka-1=6`).
- `auto.leader.rebalance.enable=true` (mặc định) + `leader.imbalance.check.interval.seconds` (lab 30s, mặc định 300s) + `leader.imbalance.per.broker.percentage` (10%) → controller tự bầu lại preferred leader.
- Lab 11 bước 6: P0 trở về kafka-1 và `leaders per broker: kafka-1=2 kafka-2=2 kafka-3=2`.
- Thủ công: `kafka-leader-election --election-type preferred --all-topic-partitions`.

## FAILURE / PRODUCTION / DEBUG

- Thời gian unavailability của một partition khi broker crash ≈ `broker.session.timeout.ms` + thời gian client refresh metadata. Giảm session timeout = failover nhanh hơn nhưng dễ fence nhầm khi GC dài.
- Nhiều partition trên một broker → nhiều election cùng lúc; KRaft xử lý theo lô nhanh hơn ZK controller cũ.

```bash
docker compose exec toolbox kcli topics -topic orders            # STATUS: leader!=preferred, UNDER-REPLICATED
docker compose exec kafka-1 kt kafka-leader-election --bootstrap-server kafka-1:29092 --election-type preferred --all-topic-partitions
docker compose logs kafka-2 | grep -i "fence"                   # controller fence broker
```
Grafana > Partition / Replication Health > "Leader (broker id) per partition", "Leader elections".

## INTERVIEW

1. Kể các bước khi leader của một partition chết (KRaft).
2. Unclean leader election là gì, vì sao tăng availability nhưng có thể mất dữ liệu?
3. Preferred leader là gì, vì sao cần rebalance leader?
4. Controlled shutdown khác crash thế nào với producer?
