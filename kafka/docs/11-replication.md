# 11 — Replication, LEO & High Watermark

> Lab: [10_replication](../labs/10_replication), [11_broker_failure](../labs/11_broker_failure), [failures/replica_out_of_sync](../labs/failures/replica_out_of_sync)

## WHAT

Mỗi partition có `replication.factor` replica trên các broker khác nhau. **Leader** nhận mọi ghi; **follower** liên tục gửi `FetchRequest` (giống consumer) tới leader để kéo dữ liệu và append vào log của mình. Replication là **pull-based**.

```text
Producer ──Produce──► Leader (kafka-1)  log: 0 1 2 3 4 5 6 7 8      LEO=9
                         ▲        ▲
              Fetch(off=7)│        │Fetch(off=9)
                          │        │
          Follower kafka-2         Follower kafka-3
          log: 0 1 2 3 4 5 6       log: 0 1 2 3 4 5 6 7 8
          LEO=7                    LEO=9

High Watermark = min(LEO của mọi replica trong ISR) = 7
Consumer chỉ đọc được offset 0..6. Offset 7, 8 đã nằm trên leader nhưng CHƯA "committed".
```

## HOW — high watermark được cập nhật thế nào

1. Leader append batch → LEO leader tăng.
2. Follower gửi `Fetch(fetchOffset = LEO_follower)`. Fetch offset đó chính là **xác nhận** follower đã có mọi thứ trước offset đó.
3. Leader cập nhật HW = min LEO của ISR, trả HW trong FetchResponse; follower cập nhật HW cục bộ.
4. `acks=all`: ProduceRequest được giữ ở **purgatory** cho tới khi HW ≥ offset của batch (hoặc hết `request.timeout`) — đây là "remote time" trong metric `kafka_network_requestmetrics_remote_time_ms{request="Produce"}`.

=> Consumer không bao giờ đọc được dữ liệu có thể biến mất khi leader đổi (vì leader mới chắc chắn có mọi thứ dưới HW).

## Leader epoch & truncation

- Mỗi lần đổi leader, controller tăng **leader epoch** (lab 11: 18 → 19). Mỗi batch ghi kèm `partitionLeaderEpoch` (thấy trong `kafka-dump-log`).
- Khi broker cũ quay lại làm follower, nó hỏi leader mới "epoch X của tôi kết thúc ở offset nào?" (`OffsetsForLeaderEpoch`) và **truncate** phần đuôi không có trên leader mới. Lab 11 bước 4:
```text
[ReplicaFetcher replicaId=1, leaderId=2] Truncating partition __consumer_offsets-48 with TruncationState(offset=0, completed=true)
```
- Phần bị truncate là dữ liệu **chưa được ack với acks=all** (trên HW cũ) — nên không mất gì đã hứa với producer. Với `acks=1`, phần đó có thể đã được ack → **mất**.

## Failure: broker chết / quay lại (lab 11, 200 msg/s, kill -9 leader)

```text
+3s, +6s : orders 0 leader kafka-1 (đã chết nhưng chưa bị fence)  epoch 18
+9s      : orders 0 leader kafka-2  replicas broker-1(DOWN),kafka-2,kafka-3  ISR kafka-2,kafka-3  epoch 19
traffic: acknowledged/failed = 11956 0 ; records appended = 11956      <- không mất, không trùng
restart  : kafka-1 truncate -> fetch -> vào lại ISR -> preferred leader election trả P0 về kafka-1
```

## acks × replication — bảng tổng hợp

| Tình huống | acks=0 | acks=1 | acks=all + min ISR 2 |
|---|---|---|---|
| Leader chết ngay sau khi nhận | mất | **mất** (đã ack) | không mất (chưa ack nếu chưa đủ ISR) |
| 1 broker down (RF3) | ghi được | ghi được | ghi được (ISR 2 ≥ 2) |
| ISR còn 1 | ghi được | ghi được (1 bản sao!) | **NOT_ENOUGH_REPLICAS** (lab 10) |
| Mất quorum KRaft | leader cũ vẫn nhận | leader cũ vẫn nhận | timeout (ISR không shrink được) |

## PERFORMANCE

- Replication nhân băng thông ghi: RF=3 → mỗi byte vào leader được gửi thêm 2 lần (Grafana "Replication bytes in/out").
- Follower fetch dùng `replica.fetch.max.bytes`, `num.replica.fetchers`; follower chậm → HW chậm → `acks=all` latency cao (failures/network_delay: p99 0.022s → 2.485s khi thêm 200ms trễ).

## PRODUCTION

- RF=3, min ISR=2, rack awareness (`broker.rack`) để 3 replica ở 3 AZ.
- Theo dõi `UnderReplicatedPartitions`, `UnderMinIsrPartitionCount`, `AtMinIsrPartitionCount`, `IsrShrinksPerSec/IsrExpandsPerSec`, `ReplicaFetcherManager MaxLag`.

## INTERVIEW

1. HW là gì, vì sao consumer không đọc được record trên HW?
2. Follower replicate bằng cơ chế gì? (pull fetch)
3. Leader epoch dùng để làm gì? Truncation xảy ra khi nào và có mất dữ liệu đã ack không?
4. Với acks=1, vẽ timeline mất dữ liệu.
