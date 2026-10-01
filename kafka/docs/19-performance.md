# 19 — Performance: throughput, latency, scaling

> Lab: [labs/performance](../labs/performance) (kết quả: `labs/performance/last-run.txt`), [17_backpressure](../labs/17_backpressure), [12_hot_partition](../labs/12_hot_partition)

> Số liệu dưới đây đo trên **một laptop** (Docker Desktop, 8 CPU, 8GB RAM cho VM, 3 broker cùng một VM, loopback network, 1KB JSON record, 100k record/lần chạy). Hãy đọc **tương đối** (A nhanh hơn B bao nhiêu lần), không phải con số tuyệt đối cho production.

## 1. Partition count (A1: producer, A2: consumer)

```text
A1 producer (acks=all, lz4, linger 5ms)                          A2 consumer (consumers = partitions, 1ms work/record)
partitions=1   463 278 rec/s  p99  50ms  1000 rec/batch          partitions=1    380 rec/s
partitions=3   591 465 rec/s  p99  52ms   877 rec/batch          partitions=3   1139 rec/s
partitions=6   485 665 rec/s  p99 101ms   532 rec/batch          partitions=6   2150 rec/s
partitions=12  268 123 rec/s  p99 230ms   314 rec/batch          partitions=12  4588 rec/s
```
- Consumer: tuyến tính theo số partition (vì consumer bị giới hạn bởi *thời gian xử lý*, không phải Kafka).
- Producer (một client): nhiều partition hơn → mỗi batch ít record hơn → nhiều request hơn → throughput **giảm** ở 12 partition. Trong cluster thật nhiều producer, nhiều broker, nhiều partition giúp rải tải lên nhiều disk/CPU.

## 2. acks (B)

```text
acks=0                 653 646 rec/s  p50 25ms  p99 43ms
acks=1                 473 943 rec/s  p50 36ms  p99 73ms
acks=all (idempotent)  584 133 rec/s  p50 29ms  p99 48ms
```
Trên một VM, replication qua loopback gần như miễn phí → khác biệt nằm trong nhiễu đo. Kết luận **không** được rút ra từ bảng này là "acks=all nhanh hơn acks=1". Trên mạng thật: acks=all cộng thêm ≥1 RTT leader↔follower + thời gian follower fetch (`replica.fetch.wait.max.ms` không ảnh hưởng vì fetch được đánh thức khi có dữ liệu). Quan sát đúng chi phí đó qua metric broker `remote_time_ms` và lab failures/network_delay (thêm 200ms trễ → p99 produce 22ms → 2.5s).

## 3. Batching (C)

```text
linger=0   batch=16KB    66 945 rec/s  p50 261ms  6672 batches (15 rec/batch)
linger=5ms batch=1MB    283 642 rec/s  p50  59ms   174 batches (575 rec/batch)
linger=20ms batch=1MB   336 170 rec/s  p50  39ms   175 batches (571 rec/batch)
```
Low-latency config (linger 0, batch nhỏ) chỉ thực sự "low latency" khi **tải thấp**. Khi tải cao, hàng nghìn request nhỏ xếp hàng (5 in-flight/broker) → latency còn *cao hơn*. High-throughput config (linger 10–50ms, batch 256KB–1MB) thêm tối đa `linger` vào latency khi tải thấp.

## 4. Compression (D, JSON compressible)

```text
none    313 842 rec/s  wire 103.9MB  ratio 1.00  client cpu 0.14s
gzip    260 165 rec/s  wire  20.5MB  ratio 5.07  client cpu 0.65s
snappy  174 670 rec/s  wire  25.1MB  ratio 4.14  client cpu 0.33s
lz4     264 868 rec/s  wire  35.5MB  ratio 2.93  client cpu 0.36s
zstd    339 710 rec/s  wire  19.2MB  ratio 5.41  client cpu 0.57s
```
Lợi ích thật của nén = ít network (×RF vì replication!), ít disk, ít page cache — loopback không phản ánh được phần network. Đổi lại CPU producer (nén) và consumer (giải nén); broker không tốn CPU nếu `compression.type=producer`. Đặt `compression.type` khác codec producer trên topic → broker phải **nén lại** (tốn CPU broker).

## 5. Consumer scaling (E, topic 6 partition, 1ms work/record)

```text
consumers=1   379 rec/s
consumers=2   749 rec/s
consumers=3  1109 rec/s
consumers=6  2298 rec/s
consumers=8  2386 rec/s   active=6   bench-consumer-6/7: IDLE (no partition)
```
Plateau đúng ở số partition.

## 6. Backpressure (lab 17)

```text
producer 5000 msg/s, order-consumers ~430 msg/s (5ms delay + Redis + sync produce)
t=30s lag=137 244   e2e p95=29s → 53s
producer dừng: consumer drain ~430/s ; bỏ delay: ~2900/s → lag 0
```
Kafka là buffer: không có backpressure tới producer (trừ khi broker/disk bão hoà) — consumer chậm chỉ làm **lag** và **end-to-end latency** tăng. Retention phải đủ dài để consumer kịp đuổi; nếu không → mất dữ liệu (`OFFSET_OUT_OF_RANGE`).

## 7. Hot partition (lab 12)

80% record cùng key `order-HOT` → P5 nhận 83.5%, lag P5 = 4753 trong khi các partition khác 0; consumer giữ P5 xử lý 259 rec/s, những partition khác ~18 rec/s. Thêm consumer **không giúp** (một partition chỉ một consumer).

## Tuning checklist

| Mục tiêu | Producer | Broker | Consumer |
|---|---|---|---|
| Throughput | linger 10–50ms, batch 256KB–1MB, zstd/lz4, nhiều partition/producer | `num.io.threads`, `num.network.threads`, disk nhanh, page cache lớn | `fetch.min.bytes` lớn, `max.poll.records` lớn, xử lý song song, batch DB writes |
| Latency | linger 0–5ms, acks theo yêu cầu durability | ít partition/broker, follower nhanh | `fetch.max.wait.ms` nhỏ, xử lý nhanh |
| Durability | acks=all, idempotent | RF 3, min ISR 2, rack aware | commit sau xử lý |

## Latency end-to-end gồm những gì

```text
linger + batching + compression + network + leader append + replication (acks=all) + HW propagation
+ consumer fetch wait + queue trong consumer (LAG!) + processing
```
Thường thành phần lớn nhất trong production là **lag** (record chờ trong log) — metric `end_to_end_latency_seconds` của lab đo đúng `now − record timestamp`.

## INTERVIEW

1. Làm sao tăng throughput producer? Đánh đổi gì?
2. Vì sao thêm consumer không tăng throughput? (≥ số partition, hot partition, nút cổ chai downstream)
3. Compression nào tốt nhất? (tuỳ — trả lời bằng tiêu chí)
4. Ước lượng end-to-end latency gồm những phần nào?
