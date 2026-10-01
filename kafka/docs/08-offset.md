# 08 — Offset: log start, LEO, HW, position, committed, lag

> Lab: [07_offsets](../labs/07_offsets), [08_delivery_semantics](../labs/08_delivery_semantics) · Doc liên quan: [26-consumer-offsets-internals](26-consumer-offsets-internals.md)

## WHAT — các loại offset

```text
Partition orders-3 (leader)

offset:  ... 4110 4111 4112 4113 4114 4115 4116 4117 4118 4119 4120
             ^                   ^              ^                   ^
             log start offset    committed      position            LEO (log end offset, leader)
             (cũ nhất còn giữ,   (group đã      (record tiếp        = offset sẽ gán cho record
              retention đẩy lên)  commit)        theo consumer       tiếp theo
                                                 sẽ fetch, RAM)
                                                          ^
                                                          High Watermark: mọi replica ISR đã có tới đây
                                                          (consumer chỉ đọc được < HW)

lag = HW (log end offset mà consumer thấy được) - committed offset
```

| Offset | Ở đâu | Ai tăng |
|---|---|---|
| Log start offset | broker | retention / delete-records / compaction |
| LEO | mỗi replica | append (leader) / fetch (follower) |
| High watermark | leader (gửi kèm cho follower & consumer) | khi follower trong ISR fetch tới |
| Last stable offset | leader | khi transaction kết thúc (read_committed) |
| Position | consumer RAM | sau mỗi poll |
| Committed | `__consumer_offsets` | OffsetCommit từ consumer (hoặc admin reset) |

`kafka-get-offsets --time -2` = log start, `--time -1` = latest (HW). Lab 07:
```text
earliest: orders:0:0 ...          latest: orders:0:4084 orders:1:4169 ...
GROUP                  TOPIC  PARTITION CURRENT-OFFSET LOG-END-OFFSET LAG
order-processing-group orders 1         4169           4169           0
```

## HOW — commit

- Commit offset **N+1** sau khi xử lý xong offset N.
- Commit theo **partition**, thường cho cả batch (commit offset lớn nhất đã xử lý liên tục).
- Commit đồng bộ (đợi coordinator xác nhận) hay bất đồng bộ (nhanh, có thể "lùi" nếu commit cũ tới sau commit mới — Java dùng commitAsync + commitSync khi đóng).

### Auto commit vs manual commit

| | Auto (`enable.auto.commit=true`, mỗi 5s) | Manual |
|---|---|---|
| Khi nào commit | timer; Java/franz-go commit offset của **lần poll trước** khi poll lại | khi app quyết định (sau side effect) |
| Duplicate khi crash | tới ~5s dữ liệu | chỉ batch chưa commit |
| Mất message | Có thể nếu app xử lý bất đồng bộ (đẩy sang thread khác rồi poll tiếp) hoặc chế độ greedy | Không (nếu commit sau xử lý) |
| Lag quan sát | răng cưa theo chu kỳ commit | mượt |

Lab 07 bước 4 (analytics-group dùng auto commit, order-processing-group manual):
```text
t= 1s analytics-group lag=18    order-processing-group lag=1
t= 2s analytics-group lag=152   order-processing-group lag=0
t= 3s analytics-group lag=280   order-processing-group lag=0
t= 4s analytics-group lag=406   order-processing-group lag=0
t= 5s analytics-group lag=30    order-processing-group lag=0      <- commit 5s vừa chạy
```
Analytics *xử lý* kịp, nhưng lag (tính theo committed) trông như đang tụt 400 record — đừng hoảng khi thấy răng cưa; alert nên dùng xu hướng (deriv) hoặc ngưỡng > commit interval × rate.

### Failure scenarios
```text
consume -> COMMIT -> process -> CRASH      => message LOST     (lab 08 B: deliveries=∅)
consume -> process -> CRASH (chưa commit)  => DUPLICATE        (lab 08 A: deliveries=2)
consume -> CRASH trước process (chưa commit) => xử lý lại, OK  (lab 08 C: deliveries=1)
```

## Replay / reprocess

Offset là con trỏ → muốn đọc lại chỉ cần dời committed offset (group phải **inactive**):

```bash
kt kafka-consumer-groups --bootstrap-server kafka-1:29092 --group G --topic orders --reset-offsets --to-earliest --execute
kt kafka-consumer-groups ... --topic orders:0 --reset-offsets --shift-by -5 --execute
kt kafka-consumer-groups ... --topic orders --reset-offsets --to-datetime 2026-10-01T10:10:00.000 --execute
kt kafka-consumer-groups ... --reset-offsets --to-offset 1234 | --to-latest | --by-duration PT10M
```
Không có `--execute` = dry run. Lab 07 bước 5 tạo group mới `lab-07-replay` *chỉ bằng commit*, không có member nào, rồi consume 5 record đúng từ offset đã đặt.

Use case: sửa bug consumer rồi xử lý lại 2 giờ dữ liệu; bootstrap service mới từ đầu topic; bỏ qua backlog độc (`--to-latest`). **Lưu ý**: replay = duplicate side effect → consumer phải idempotent.

## Lỗi thường gặp

- `OFFSET_OUT_OF_RANGE`: committed offset < log start (dữ liệu đã bị retention xoá) → reset theo `auto.offset.reset` → có thể **mất** (latest) hoặc đọc lại nhiều (earliest).
- Commit offset sai (commit N thay vì N+1) → record cuối bị xử lý 2 lần mỗi lần restart.
- Commit cho partition đã bị revoke (generation cũ) → `ILLEGAL_GENERATION`/`FENCED_INSTANCE_ID`.

## INTERVIEW

1. Phân biệt LEO, HW, committed offset, position.
2. Lag tính thế nào, tính ở đâu? Vì sao lag auto-commit có hình răng cưa?
3. Viết timeline cho duplicate và cho message loss.
4. Làm sao xử lý lại dữ liệu của 1 giờ trước? Điều kiện?
5. Consumer bị offline lâu hơn retention thì sao?
