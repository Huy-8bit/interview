# 04 — Topic & Partition (và cách chọn số partition)

> Lab: [02_partitions](../labs/02_partitions), [03_message_key](../labs/03_message_key), [performance](../labs/performance) · Config: [kafka/topics/topics.conf](../kafka/topics/topics.conf)

## WHAT

- **Topic**: tên logic của một stream (`orders`, `payments`...), kèm config riêng (retention, cleanup.policy, min ISR, max.message.bytes...).
- **Partition**: một log append-only độc lập của topic. Offset chỉ có nghĩa **trong một partition** (`orders P3 @518` khác `orders P5 @518`).
- **Replica**: bản sao của partition trên một broker. `replication.factor=3` → 3 replica: 1 leader + 2 follower.

```text
Topic: orders  (6 partitions, RF=3, min.insync.replicas=2) — trạng thái thật trong lab

       P0                 P1                 P2                 P3                 P4                 P5
        │                  │                  │                  │                  │                  │
kafka-1 LEADER     kafka-2 LEADER     kafka-3 LEADER     kafka-1 LEADER     kafka-2 LEADER     kafka-3 LEADER
kafka-2 replica    kafka-3 replica    kafka-1 replica    kafka-2 replica    kafka-3 replica    kafka-1 replica
kafka-3 replica    kafka-1 replica    kafka-2 replica    kafka-3 replica    kafka-1 replica    kafka-2 replica

leaders per broker: kafka-1=2 kafka-2=2 kafka-3=2   (replica đầu tiên = preferred leader)
```

## WHY — partition để làm gì

1. **Song song**: trong một consumer group, một partition chỉ được giao cho **một** consumer → số consumer *có việc* ≤ số partition (lab 05: 8 consumer, 6 partition → 2 IDLE; performance E: 6 consumer 2298 rec/s, 8 consumer 2386 rec/s).
2. **Thứ tự**: Kafka chỉ đảm bảo thứ tự trong một partition (lab 04).
3. **Phân tải**: leader của các partition rải đều các broker → ghi/đọc được chia đều.
4. **Lưu trữ**: một partition phải nằm gọn trên một broker (một disk) → partition nhiều cho phép topic lớn hơn một máy.

## HOW — record chọn partition thế nào

```text
key != null :  partition = toPositive(murmur2(keyBytes)) % numPartitions      (Java client & franz-go giống nhau)
key == null :  sticky partitioner (KIP-480/794): dồn vào 1 partition cho tới khi batch gửi đi, rồi đổi
```

Lab 03 (dữ liệu thật):
```text
KEY        murmur2(key)  & 0x7fffffff  % 6 = PARTITION
order-100  -955961047    1191522601    P1
order-101  1112104930    1112104930    P4
# cùng key với 12 partitions:  order-101 -> P10, order-102 -> P6     (thêm partition = đổi mapping!)

2000 record null key, SYNC  -> 2000 produce batches, rải đều: map[0:319 1:362 2:332 3:341 4:318 5:328]
2000 record null key, ASYNC -> 1 produce batch, tất cả vào  map[2:2000]          (sticky)
```

## INTERNAL — partition trên disk

Mỗi replica là một thư mục `/<log.dirs>/<topic>-<partition>/`:

```text
/var/lib/kafka/data/orders-0/
  00000000000000000000.log        # dữ liệu: các RecordBatch nối tiếp nhau
  00000000000000000000.index      # offset index: offset tương đối -> vị trí byte (thưa, mỗi ~4KB)
  00000000000000000000.timeindex  # timestamp -> offset
  00000000000000000524.snapshot   # producer state snapshot (producerId -> last sequence) cho idempotence
  leader-epoch-checkpoint         # epoch -> start offset (dùng khi truncate sau failover)
  partition.metadata              # topic_id
```
Chi tiết segment/index ở [27-log-storage](27-log-storage.md).

## PERFORMANCE & TRADE-OFF — "nhiều partition = nhanh hơn" là sai một nửa

| Yếu tố | Nhiều partition hơn thì... |
|---|---|
| Consumer parallelism | ✅ Tăng trần số consumer hoạt động (performance A2: 1→380, 3→1139, 6→2150, 12→4588 rec/s với 1ms work/record) |
| Producer batching | ❌ Một producer chia record ra nhiều partition → batch nhỏ hơn → nhiều request hơn (performance A1: 1 partition 1000 rec/batch, 12 partition 314 rec/batch, throughput giảm còn 268k rec/s so với ~485k–591k) |
| Ordering | ❌ Không đổi ý nghĩa, nhưng **tăng partition sau này đổi mapping key → partition** → phá ordering theo key trong giai đoạn chuyển |
| Metadata | ❌ Mỗi partition = state trong controller + metadata response lớn hơn |
| Rebalance | ❌ Nhiều partition cần assign/revoke, nhiều offset cần commit |
| File handles | ❌ Mỗi segment mở 3 file (log, index, timeindex). Lab: kafka-1 mở 335 fd với 118 replica |
| Replication | ❌ Nhiều replica fetcher work, nhiều partition phải bầu leader khi broker chết (failover lâu hơn) |
| Memory | ❌ Producer giữ một batch buffer / partition; consumer fetch buffer / partition |
| End-to-end latency | `acks=all` phải chờ follower replicate *tất cả* partition; với rất nhiều partition/broker, follower fetch tốn thời gian hơn |

### Vì sao lab chọn những con số này

| Topic | Partitions | Lý do |
|---|---|---|
| `orders`, `payments` | 6 | Hiện 3 consumer instance; cho phép scale lên 6 mà **không phải thêm partition** (tránh đổi mapping key). Tốc độ đơn lẻ mỗi partition (vài trăm–vài nghìn msg/s) đủ cho lab |
| `analytics-events` | 12 | Fan-in nhiều nhất, xử lý batch rẻ, muốn tối đa 12 worker |
| `notifications` | 3 | Lưu lượng thấp, thứ tự theo user là đủ |
| `retry-*`, `*-dlq` | 3 | Kênh phụ, ít dữ liệu; DLQ cần bền (RF=3) chứ không cần throughput |
| `retention-demo` | 1 | Dễ quan sát segment file trên disk |
| `user-profile-compacted` | 3 | State topic nhỏ |

### Cách tính số partition (production)

```text
P >= max( T / Pp ,  T / Pc ,  C_max )
  T  = throughput mục tiêu (MB/s hoặc msg/s) ở peak, có tính tăng trưởng 1–2 năm
  Pp = throughput 1 partition phía producer đo được (benchmark với acks/compression thực tế)
  Pc = throughput 1 partition phía consumer = 1 / thời gian xử lý mỗi record (thường là nút cổ chai!)
  C_max = số consumer instance tối đa muốn chạy song song
```

Ví dụ: 20 000 msg/s, consumer xử lý 4 ms/record (Pc = 250 msg/s/partition) → cần ≥ 80 partition *hoặc* xử lý song song trong partition (giữ ordering per key bằng key-based worker pool). Đây là lý do "luôn dùng 12 partition" là quy tắc vô nghĩa.

Quy tắc thực dụng: chọn đủ cho 1–2 năm, tránh tăng sau này với topic cần ordering theo key; nếu phải tăng, cân nhắc tạo topic mới + migrate.

## PRODUCTION

- Không bật auto-create; topic được quản lý như code (lab: `topics.conf` + `create-topics.sh` idempotent, re-apply config).
- RF=3, `min.insync.replicas=2` cho topic nghiệp vụ.
- Theo dõi phân phối leader (`leaders per broker`, metric `preferredreplicaimbalancecount`).

## DEBUG

```bash
./scripts/describe-topics.sh orders --raw         # leader/replicas/ISR/ELR
./scripts/partition-stats.sh orders               # số record mỗi partition, skew
docker compose exec kafka-1 ls -la /var/lib/kafka/data/orders-0
docker compose exec kafka-1 kt kafka-dump-log --files /var/lib/kafka/data/orders-0/00000000000000000000.log --print-data-log | head
```

## INTERVIEW

1. Tăng partition của topic đang dùng key-based ordering có vấn đề gì?
2. Có thể giảm số partition không? (Không. Phải tạo topic mới.)
3. Vì sao nhiều partition hơn có thể *giảm* throughput của một producer?
4. 6 partition, 8 consumer cùng group thì sao? 6 partition, 2 group mỗi group 3 consumer thì sao?
5. Bạn chọn số partition cho topic 50k msg/s như thế nào?
