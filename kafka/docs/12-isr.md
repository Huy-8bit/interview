# 12 — ISR, min.insync.replicas & ELR

> Lab: [10_replication](../labs/10_replication), [failures/replica_out_of_sync](../labs/failures/replica_out_of_sync)

## WHAT

**ISR (In-Sync Replicas)** = tập replica (gồm leader) đang "theo kịp" leader. Chỉ replica trong ISR được tính khi:
- quyết định High Watermark,
- `acks=all` chờ xác nhận,
- bầu leader sạch (clean leader election).

```text
Leader P0 = kafka-1     Replicas: kafka-1, kafka-2, kafka-3
ISR (bình thường):      kafka-1, kafka-2, kafka-3
kafka-3 tụt > replica.lag.time.max.ms:
ISR:                    kafka-1, kafka-2              <- acks=all chỉ cần 1,2 ; HW bỏ qua kafka-3
```

## HOW — khi nào một follower bị loại / được nhận lại

- Follower bị loại khỏi ISR nếu **không bắt kịp LEO của leader** trong `replica.lag.time.max.ms` (lab 10s, mặc định 30s). Tiêu chí là *thời gian* kể từ lần cuối follower bắt kịp, không phải số record lệch.
- Leader gửi `AlterPartition` lên controller → controller ghi metadata → mọi broker thấy ISR mới.
- Follower bắt kịp lại (LEO ≥ HW) → leader gửi AlterPartition để **expand** ISR.

**Chi tiết quan sát được trong lab 10 (rất dễ bị hỏi vặn):** khi chặn kafka-2 fetch, **chỉ partition có dữ liệu mới** (P3, P5 — nơi lab ghi vào) bị shrink:
```text
Topic: orders  Partition: 3  Leader: 1  Replicas: 1,2,3  Isr: 1   Elr: 2
Topic: orders  Partition: 0  Leader: 1  Replicas: 1,2,3  Isr: 1,2 Elr:       <- không có ghi mới
```
Partition không có ghi mới: LEO follower == LEO leader → follower vẫn được coi là "caught up" dù không fetch. ISR phản ánh **độ trễ dữ liệu**, không phải liveness. (Liveness của broker do controller xử lý qua heartbeat/fence.)

## min.insync.replicas

Ngưỡng tối thiểu ISR để leader **chấp nhận** ghi với `acks=all`:
- ISR ≥ min ISR → ghi bình thường.
- ISR < min ISR → leader trả `NOT_ENOUGH_REPLICAS` (retriable). Lab 10 bước 2:
```text
acks=all -> ERROR: record 0: records have timed out before they were able to be produced
broker kafka-1 answered NOT_ENOUGH_REPLICAS 6 times: the client retried (retriable error) until its 8s delivery timeout
acks=1   -> produced topic=orders partition=3 offset=6776      <- chỉ 1 bản sao
kafka_server_replicamanager_underminisrpartitioncount 6.0
```
`min.insync.replicas` **không** ảnh hưởng `acks=0/1` và **không** ảnh hưởng consumer (đọc vẫn được).

### Durability trade-off

| RF / min ISR | Chịu được để vẫn GHI (acks=all) | Không mất dữ liệu đã ack khi |
|---|---|---|
| 3 / 1 | 2 broker hỏng | không đảm bảo (ISR có thể chỉ còn leader) |
| **3 / 2** (khuyến nghị) | 1 broker hỏng | tối đa 1 broker mất disk |
| 3 / 3 | 0 broker hỏng (mọi bảo trì đều chặn ghi) | 2 broker mất disk |
| 5 / 3 | 2 broker hỏng | 2 broker mất disk |

## ELR — Eligible Leader Replicas (KIP-966, Kafka 4.x)

Vấn đề cũ: khi ISR co lại dưới min ISR rồi leader chết, replica bị loại khỏi ISR vẫn có thể *có đủ dữ liệu đã commit* nhưng không được bầu (vì ngoài ISR) → partition offline hoặc phải unclean election.

ELR: khi ISR < min ISR, các replica bị loại (mà vẫn có dữ liệu tới HW) được giữ trong **ELR** → controller có thể bầu chúng làm leader **an toàn**. Thấy trực tiếp trong lab: `Isr: 1  Elr: 2`. Metric `kafka_controller_controllerstats_electionfromeligibleleaderreplicas_total` đếm số lần bầu từ ELR/ISR sạch.

## FAILURE / PRODUCTION / DEBUG

- `IsrShrinksPerSec` tăng đột biến: broker chậm (GC, disk), network, quá tải replica fetcher. failures/replica_out_of_sync: 17 lần shrink khi chặn port replication của kafka-3, ghi vẫn thành công vì ISR còn 2.
- ISR flapping (shrink/expand liên tục): `replica.lag.time.max.ms` quá thấp so với độ trễ thật.

```bash
./scripts/describe-topics.sh orders --raw                         # Isr / Elr / LastKnownElr
docker compose exec kafka-1 kt kafka-topics --bootstrap-server kafka-1:29092 --describe --under-replicated-partitions
docker compose exec kafka-1 kt kafka-topics --bootstrap-server kafka-1:29092 --describe --under-min-isr-partitions
./scripts/net-fault.sh block-replication 3 ; ./scripts/net-fault.sh clear 3
```
Grafana > Partition / Replication Health.

## INTERVIEW

1. ISR là gì? Replica bị loại khỏi ISR khi nào?
2. RF=3, min ISR=2, acks=all: tắt 1 broker? tắt 2 broker?
3. `min.insync.replicas` có tác dụng với acks=1 không?
4. Vì sao một follower không fetch vẫn có thể nằm trong ISR?
5. ELR giải quyết vấn đề gì?
