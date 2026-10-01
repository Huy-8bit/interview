# Lab 07 — Offsets, lag, replay, __consumer_offsets

**Mục tiêu**: thấy log start / log end / committed / lag bằng số thật; lag tăng/giảm; răng cưa auto-commit; replay bằng reset-offsets; commit nằm ở partition nào của `__consumer_offsets`.
**Đọc trước**: [docs/08](../../docs/08-offset.md), [docs/26](../../docs/26-consumer-offsets-internals.md)

## Chạy
```bash
./labs/07_offsets/run.sh
```

## Quan sát (kết quả thật)
```text
earliest orders:0:0 ...   latest orders:0:4084 orders:1:4169 ...
consumers stopped 10s @50 msg/s: total lag 534 (mỗi partition 82–101) ; 5s sau restart: lag 2
auto-commit (analytics-group): lag 18 -> 152 -> 280 -> 406 -> 30 -> 159 -> 296 -> 427 -> 56   (commit mỗi 5s)
manual commit (order-processing-group): lag 0–2
reset-offsets --to-earliest / --shift-by -5 / --to-datetime  -> group lab-07-replay tồn tại không cần member
consume 5 record as lab-07-replay -> bắt đầu đúng tại committed offset (P1 @5056 ...)
group lab-07-replay -> __consumer_offsets partition 21 (leader kafka-2 = coordinator)
{"key":{"type":1,"data":{"group":"lab-07-replay","topic":"orders","partition":0}},"value":{"version":4,"data":{"offset":0,...}}}
__consumer_offsets: P41 62149 (50.8%), P14 32693, P22 22481 ... HOT PARTITION (group commit nhiều)
```

## Câu hỏi
1. Lag analytics 406 có nghĩa analytics đang chậm không?
2. Reset offset khi group đang chạy thì sao?
3. Vì sao một vài partition của `__consumer_offsets` nóng?
