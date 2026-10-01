# 05 — Producer: từ `Produce()` tới ack

> Code: [services/producer](../services/producer/main.go), [pkg/kafka/client.go](../pkg/kafka/client.go) · Lab: 01, 03, 16, performance

## WHAT

Producer là client gửi record vào topic. Producer quyết định: **partition**, **batching**, **compression**, **mức xác nhận (acks)**, **retry**, **idempotence/transaction**.

## HOW — đường đi bên trong client

```text
app gọi Produce(record{topic, key, value, headers})
   │
   ├─ 1. serialize (app làm: JSON) ───────────────► bytes
   ├─ 2. partitioner: murmur2(key) % N | sticky (null key)
   ├─ 3. append vào RecordBatch đang mở của (topic, partition) trong buffer
   │        buffer giới hạn bởi MaxBufferedRecords / buffer.memory
   │        -> đầy thì Produce() BLOCK (backpressure phía producer)
   ├─ 4. batch "sẵn sàng" khi: đủ batch.size (ProducerBatchMaxBytes)  HOẶC  hết linger.ms
   ├─ 5. compress cả batch (none/gzip/snappy/lz4/zstd)
   ├─ 6. gom các batch cùng leader broker vào 1 ProduceRequest
   │        tối đa N request in-flight / broker (idempotent: 5)
   ▼
leader broker: validate -> append -> (acks=all: chờ ISR) -> ProduceResponse(baseOffset)
   ▼
callback / ProduceSync trả về (partition, offset) hoặc error
   lỗi retriable (NOT_LEADER, NOT_ENOUGH_REPLICAS, timeout...) -> refresh metadata, gửi lại
   cho tới RecordRetries / delivery.timeout.ms
```

## Sync vs Async (producer-service)

| | `POST /orders?mode=sync` | `POST /orders?mode=async` |
|---|---|---|
| HTTP trả về khi | broker đã ack | record vừa vào buffer |
| Biết partition/offset | ✅ (`"partition":5,"offset":518`) | ❌ (`-1`), chỉ log ở callback |
| Lỗi | trả 503 cho client | chỉ log → **client không biết** |
| Throughput | thấp (1 record/round-trip nếu gọi tuần tự) | cao |

Lab 03: 2000 record sync → 2000 batches; async → 1 batch.

## acks

```text
acks=0   Producer ──► Leader            (không chờ phản hồi; offset không biết: API trả offset -1)
acks=1   Producer ──► Leader append ──► ACK          (follower chưa chắc có)
acks=all Producer ──► Leader append ──► ISR followers fetch & có record ──► HW tăng ──► ACK
```

| acks | Mất dữ liệu khi | Latency | Ghi chú |
|---|---|---|---|
| 0 | bất kỳ lỗi mạng/broker | thấp nhất | Lỗi không bao giờ về tới producer |
| 1 | leader chết sau ack, trước khi follower kịp copy | thấp | Leader mới (follower cũ) không có record → **mất record đã ack** |
| all + min ISR 2 | ≥2 broker trong ISR cùng mất disk | cao hơn (thêm thời gian replication) | Lab 10: còn ISR=1 → `NOT_ENOUGH_REPLICAS` thay vì nhận ghi thiếu an toàn |

Đo trong lab: broker metric `kafka_network_requestmetrics_remote_time_ms{request="Produce"}` = thời gian leader *chờ follower*; xấp xỉ 0 với acks=0/1. Benchmark throughput acks=0/1/all trên cluster 1 máy (performance B: 653k / 473k / 584k rec/s) **không phân biệt rõ** vì replication qua loopback gần như miễn phí và nhiễu giữa các lần chạy lớn hơn khác biệt — trong mạng thật, acks=all thêm ít nhất 1 RTT tới follower vào latency.

## Batching & linger

- `batch.size` (franz-go `ProducerBatchMaxBytes`, lab 1MB) = trần kích thước 1 batch / partition.
- `linger.ms` = chờ thêm bao lâu để gom record trước khi gửi (franz-go mặc định 10ms; lab producer dùng 5ms).

Performance C (acks=all, không nén, 100k record 1KB):
```text
linger=0 batch=16KB     66 945 rec/s  p50 260ms  6672 batches (15 rec/batch)
linger=5ms batch=1MB   283 642 rec/s  p50  59ms   174 batches (575 rec/batch)
linger=20ms batch=1MB  336 170 rec/s  p50  39ms   175 batches (571 rec/batch)
```
Nghịch lý: linger=0 có latency p50 *cao hơn* vì 6672 request nhỏ xếp hàng (5 in-flight/broker) → queueing. Batch to làm giảm overhead per record (header, CRC, request, syscall, replication).

## Compression

Nén **cả batch** ở producer; broker lưu nguyên (nếu topic `compression.type=producer`); consumer giải nén. Performance D (JSON 1KB, compressible):

```text
compression=none     313 842 rec/s  wire 103.9MB  ratio 1.00  cpu 0.14s
compression=gzip     260 165 rec/s  wire  20.5MB  ratio 5.07  cpu 0.65s
compression=snappy   174 670 rec/s  wire  25.1MB  ratio 4.14  cpu 0.33s
compression=lz4      264 868 rec/s  wire  35.5MB  ratio 2.93  cpu 0.36s
compression=zstd     339 710 rec/s  wire  19.2MB  ratio 5.41  cpu 0.57s
```
Đọc kết quả: zstd nén tốt nhất và trong lab cũng nhanh nhất; gzip tốn CPU nhất; snappy của thư viện Go chậm hơn kỳ vọng. Trên loopback, băng thông mạng không phải nút cổ chai nên lợi ích chính của nén (giảm network/disk ×5) không phản ánh vào throughput. **Không có codec "luôn tốt nhất"**: chọn theo CPU còn dư, băng thông, chi phí storage, và đo với payload thật. Batch to → nén tốt hơn.

## Retry, ordering & idempotence

- Retry tự động với lỗi retriable. Với `max.in.flight > 1` và **không** idempotent, retry có thể đảo thứ tự (batch 1 lỗi, batch 2 thành công, batch 1 retry sau).
- **Idempotent producer** (mặc định bật ở franz-go và Java ≥3.0): broker gán **producerId (PID)**, producer đánh **sequence number** cho mỗi batch/partition; broker loại batch trùng & từ chối batch nhảy sequence → không duplicate do retry và **giữ thứ tự với tối đa 5 request in-flight**. Chi tiết + lab 16: [15-idempotence](15-idempotence.md).
- `delivery.timeout.ms` (franz-go `RecordDeliveryTimeout`): tổng thời gian tối đa cho một record (kể cả retry). Lab 10 chỉ ra hệ quả: lỗi thật (`NOT_ENOUGH_REPLICAS`, broker đếm 276 lần trong 8s) bị retry và cuối cùng client chỉ thấy *"records have timed out"* → **log/metrics phía broker là bắt buộc để biết nguyên nhân gốc**.

## Partitioner cho null key

| Partitioner | Hành vi | Dùng khi |
|---|---|---|
| sticky (mặc định) | dồn vào 1 partition tới khi batch gửi | throughput tốt, batch to |
| uniform bytes (KIP-794) | đổi partition mỗi ~batch.size, né broker chậm | mặc định Java ≥3.3 |
| round-robin | mỗi record 1 partition | gần như không nên: batch nhỏ, phá ordering (lab 04) |

## FAILURE

| Sự cố | Producer thấy |
|---|---|
| Leader chết (lab 11) | `NOT_LEADER_OR_FOLLOWER`/connection error → refresh metadata → gửi tới leader mới. 11956/11956 record an toàn, 0 failed |
| ISR < min ISR (lab 10) | `NOT_ENOUGH_REPLICAS` (retriable) → retry tới timeout |
| Mất quorum | `acks=all` timeout, `acks=1` vẫn ghi |
| Network delay 200ms (failures/network_delay) | p99 produce latency 0.022s → 2.485s |
| Producer crash (failures/producer_restart) | record đang buffer chưa ack bị mất; restart → PID mới |

## PRODUCTION checklist

```properties
acks=all
enable.idempotence=true
max.in.flight.requests.per.connection<=5
linger.ms=5..20            # theo SLA latency
batch.size=64KB..1MB
compression.type=zstd|lz4
delivery.timeout.ms=120000 # chọn theo SLA, và xử lý callback lỗi!
```
Luôn xử lý lỗi trong callback async; có **outbox** nếu sự kiện bắt nguồn từ một DB transaction.

## DEBUG

```bash
curl -s localhost:8000/config                                   # cấu hình producer-service
curl -s -XPOST 'localhost:8000/orders?acks=1&key=user_id' -d '{"user_id":1,"product_id":2,"quantity":1}'
docker compose exec toolbox kcli bench-produce -topic perf-p6 -records 50000 -linger 20ms -compression zstd
# Grafana > Producer Performance: produced_total, produce_latency_seconds, broker remote time
```

## INTERVIEW

1. Mô tả đường đi của record trong producer (serialize → partition → batch → compress → send → ack).
2. acks=1 mất dữ liệu trong kịch bản nào?
3. linger.ms tăng thì latency tăng hay giảm? (thường tăng nhẹ ở tải thấp, có thể *giảm* ở tải cao vì bớt queueing)
4. Vì sao retry có thể gây duplicate và đảo thứ tự? Idempotence xử lý thế nào?
5. Async produce nguy hiểm ở đâu?
