# 06 — Consumer: poll, fetch, process, commit

> Code: [pkg/kafka/consumer.go](../pkg/kafka/consumer.go) (Runner) · Lab: 01, 05, 06, 07, 08, 17

## WHAT

Consumer **kéo (pull)** record từ broker. Trong một consumer group, mỗi partition thuộc về đúng một member; consumer tự quản lý **vị trí đọc** (position, trong bộ nhớ) và định kỳ lưu **committed offset** (bền, trên broker).

## Những câu hỏi phải trả lời được

### 1. Consumer gửi FetchRequest tới broker nào?
Tới **leader** của partition (lấy từ metadata). Một FetchRequest gom nhiều partition có cùng leader. Fetch là **long-poll**: broker giữ request tới khi có `fetch.min.bytes` dữ liệu hoặc hết `fetch.max.wait.ms` (lab: 500ms). Đó là lý do metric `FetchConsumer` total time p99 cao (~500ms) trên topic nhàn rỗi — bình thường.

### 2. Đọc từ leader hay follower?
Mặc định **leader**. Từ Kafka 2.4 (KIP-392) consumer có thể đọc **follower cùng rack** (`client.rack` + `replica.selector.class=RackAwareReplicaSelector`) để tiết kiệm băng thông cross-AZ. Follower vẫn chỉ trả dữ liệu ≤ high watermark.

### 3. Consumer thấy dữ liệu tới đâu?
Chỉ tới **High Watermark** (offset mà mọi replica trong ISR đã có) với `read_uncommitted`; tới **Last Stable Offset** với `read_committed` (bỏ qua transaction chưa kết thúc). Record vừa được leader append nhưng chưa replicate đủ **chưa visible** — xem [11-replication](11-replication.md).

### 4. Offset nằm ở đâu?
- **Position** (record tiếp theo sẽ đọc): trong bộ nhớ consumer.
- **Committed offset**: topic nội bộ `__consumer_offsets` (50 partition, compacted), partition = `abs(hash(group.id)) % 50`, leader của partition đó là **group coordinator**. Xem [26-consumer-offsets-internals](26-consumer-offsets-internals.md).

### 5. Committed offset nghĩa là gì?
"Offset của record **tiếp theo** cần xử lý". Xử lý xong offset 518 → commit **519**. Khi consumer mới nhận partition, nó bắt đầu từ committed offset (không có → `auto.offset.reset`: earliest/latest).

### 6. Xử lý xong nhưng chưa commit rồi crash?
Record được giao lại cho consumer kế nhiệm → **duplicate** (at-least-once). Lab 08 A, dữ liệu thật:
```text
LAB FAULT: simulated crash AFTER processing, BEFORE offset commit   partition=2 offset=5521
... restart, rebalance ...
DUPLICATE delivery detected: event already processed, side effect skipped  partition=2 offset=5521
lab:order:order-lab08-dup-... => deliveries 2 reserved_qty 3      (giao 2 lần, side effect idempotent áp dụng 1 lần)
```

### 7. Commit trước rồi mới process?
Crash giữa chừng → offset đã commit → record **không bao giờ được xử lý lại** → **mất** (at-most-once). Lab 08 B: `COMMIT before processing` → crash → `deliveries` rỗng mãi mãi.

### 8. Rebalance ảnh hưởng processing ra sao?
Trong rebalance, partition bị **revoke** khỏi member A và **assign** cho B. Nếu A chưa commit những gì đã xử lý → B xử lý lại (duplicate). Eager protocol: *mọi* member dừng mọi partition; cooperative: chỉ partition bị chuyển. Runner của lab dùng `BlockRebalanceOnPoll` (không cho rebalance chen giữa lúc đang xử lý batch) + commit trong `OnPartitionsRevoked`. Xem [09-rebalancing](09-rebalancing.md).

### 9. Group coordinator làm gì?
Broker leader của partition `__consumer_offsets` tương ứng với group: quản lý membership (Join/Sync/Heartbeat hoặc ConsumerGroupHeartbeat của KIP-848), generation, nhận và lưu offset commit. Xem [07-consumer-group](07-consumer-group.md).

### 10. Heartbeat hoạt động thế nào? Session timeout khác max.poll.interval thế nào?

| | `session.timeout.ms` | `max.poll.interval.ms` |
|---|---|---|
| Phát hiện | process chết / mất mạng | process sống nhưng **xử lý quá lâu** (không gọi poll) |
| Cơ chế | heartbeat (Java: thread nền; franz-go: goroutine nền) mỗi `heartbeat.interval.ms` | Java client tự leave group nếu 2 lần poll cách nhau > giá trị này |
| Lab | 10s (order-consumer) — crash phát hiện sau 10.6s (lab 06 B) | franz-go dùng `RebalanceTimeout` (lab 30s) làm thời gian tối đa member được phép chậm khi rebalance đang diễn ra |

Hệ quả: tăng `session.timeout` = phát hiện crash chậm hơn; xử lý chậm (batch lớn × thời gian/record) vượt max poll interval → bị đá khỏi group → rebalance liên tục ("rebalance storm"). Lab 05/doc 21 có cả trường hợp "ghost member" tồn tại 45s (session timeout mặc định) vì LeaveGroup bị mất khi coordinator đang chuyển.

### 11. Lag tính thế nào?
`lag = log end offset (HW) − committed offset`, tính **ở phía client/admin** (broker không có metric lag per group). lag-exporter làm đúng điều đó bằng Admin API. Lag dựa trên **committed** offset nên với auto-commit 5s, lag có hình răng cưa (lab 07: 18 → 152 → 280 → 406 → 30 mỗi 5s).

## HOW — vòng lặp của Runner trong lab

```text
for {
  fetches := PollRecords(ctx, MAX_POLL_RECORDS)          // nhận batch, rebalance bị chặn tới AllowRebalance()
  if COMMIT_MODE == before-process { commit(polled) }     // at-most-once
  for mỗi partition trong batch (song song, tối đa CONCURRENCY):
      for mỗi record (TUẦN TỰ trong partition -> giữ thứ tự):
          sleep(PROCESSING_DELAY)                          // lab backpressure
          err := handler(record)  (+ INLINE_RETRIES)
          err != nil -> retry topic / DLQ (sync produce, bắt buộc thành công, nếu không -> crash)
          markProcessed(record)                            // pending[topic][partition] = offset+1
  AfterBatch()                                             // batch processing (analytics)
  if COMMIT_MODE == manual { CommitOffsetsSync(pending) }  // at-least-once
  AllowRebalance()
}
SIGTERM: dừng poll -> xử lý nốt batch hiện tại -> commit -> LeaveGroup (Close)  => rebalance ngay (lab 06 A: 478ms)
```

Log mỗi record (đủ để debug):
```text
msg=processed consumer=order-consumer-2 group=order-processing-group topic=orders partition=5 offset=518
              key=order-1edb61a132ae event_type=OrderCreated hw=519 lag=0 took=8.17ms
```
`hw` lấy từ FetchResponse → `lag` tại thời điểm fetch, không cần gọi admin API.

## Commit modes (biến `COMMIT_MODE`)

| Mode | Hành vi | Semantics |
|---|---|---|
| `manual` (order/payment/notification) | commit sau khi xử lý xong batch + trong onRevoked + khi shutdown | at-least-once |
| `before-process` | commit ngay sau poll | at-most-once (lab 08 B mất message) |
| `auto` (analytics) | client commit mỗi 5s offset của **lần poll trước** | gần at-least-once, có thể duplicate tới 5s dữ liệu |
| `auto-greedy` | commit mọi thứ đã poll | có thể mất khi crash |

## FAILURE

| Sự cố | Quan sát trong lab |
|---|---|
| Consumer SIGTERM | LeaveGroup → các member khác nhận partition sau 478ms |
| Consumer SIGKILL | Partition "mồ côi" tới khi session timeout (10.6s); lag các partition đó tăng (46, 49) |
| Consumer chậm | lag tăng 137k (lab 17), end-to-end latency p95 53s |
| Poison message | retry ×3 → DLQ (lab 09) |
| Broker chết | fetch error → refresh metadata → fetch leader mới; `partitions LOST` nếu coordinator mất (lab 11) |

## PERFORMANCE

- Song song tối đa = số partition (performance E: 6→2298, 8→2386 rec/s).
- Song song **trong** partition (giữ thứ tự theo key) là kỹ thuật nâng cao: key-hash worker pool, commit offset liên tục nhỏ nhất đã hoàn tất.
- `max.poll.records`, `fetch.max.bytes`, `max.partition.fetch.bytes` điều chỉnh kích thước batch; batch lớn = throughput tốt, rebalance chậm hơn.
- Head-of-line blocking: một partition nóng trong batch giữ cả batch (lab 12: P0 bị lag 122 vì cùng consumer với P5 nóng).

## PRODUCTION

- Commit **sau** khi side effect bền vững; side effect phải idempotent (event_id / idempotency key).
- Graceful shutdown (SIGTERM, `stop_grace_period`) — dừng nhận việc, xong việc dở, commit, LeaveGroup.
- Cooperative-sticky hoặc KIP-848; static membership (`group.instance.id`) cho rolling restart.
- Alert theo **lag tăng liên tục** và **thời gian lag** (end-to-end latency), không chỉ lag tuyệt đối.

## DEBUG

```bash
curl -s localhost:8011/admin/state | jq           # assignment, commit mode, delay của instance
curl -s -XPOST 'localhost:8011/admin/delay?ms=50'  # giả lập xử lý chậm
docker compose exec toolbox kcli group -group order-processing-group -watch 2s
docker compose exec kafka-1 kt kafka-consumer-groups --bootstrap-server kafka-1:29092 --describe --group order-processing-group --members --verbose
```

## INTERVIEW
Mười một câu hỏi ở trên chính là bộ câu hỏi phỏng vấn. Thêm:
- Làm sao xử lý song song nhiều record trong một partition mà vẫn đúng thứ tự theo key?
- Vì sao không nên commit offset từng record một với throughput cao? (tải lên coordinator / `__consumer_offsets`; lab 07 thấy partition 41 của `__consumer_offsets` có 62k record vì group commit mỗi batch)
