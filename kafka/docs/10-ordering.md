# 10 — Ordering

> Lab: [04_ordering](../labs/04_ordering), [03_message_key](../labs/03_message_key)

## WHAT

Kafka đảm bảo: **trong một partition**, consumer đọc record theo đúng thứ tự offset, và offset được gán theo thứ tự broker append. **Không** có global ordering giữa các partition.

## HOW — để có ordering theo thực thể

1. Chọn **key** = định danh thực thể cần thứ tự (order_id, user_id, account_id).
2. Cùng key → cùng partition (murmur2 % N).
3. Producer phải gửi theo thứ tự *và* không đảo khi retry → **idempotent producer** (cho phép ≤5 in-flight mà vẫn giữ thứ tự nhờ sequence number).
4. Consumer xử lý **tuần tự trong partition** (Runner: song song giữa partition, tuần tự trong partition).

## Kết quả lab 04 (dữ liệu thật)

Có key (3 order × 6 event, gửi async xen kẽ):
```text
order-52880-0  partitions=P5  IN ORDER  seq: 1(P5@355) 2(P5@356) 3(P5@357) 4(P5@358) 5(P5@359) 6(P5@360)
order-52880-1  partitions=P1  IN ORDER  seq: 1(P1@400) ...
consumer receive order: 1#1 1#2 1#3 1#4 1#5 1#6 0#1 0#2 ... 2#6      <- giữa các key KHÔNG theo thứ tự gửi
```

Không key, round-robin:
```text
order-53098-0  partitions=P0,P3  OUT OF ORDER  seq: 1(P0@358) 3(P0@359) 5(P0@360) 2(P3@368) 4(P3@369) 6(P3@370)
```

Không key, sticky (mặc định): cả burst vào **một** batch P2 → "IN ORDER" — may mắn, không phải đảm bảo.

Qua pipeline thật (`POST /orders/order-lab04/events?count=10` → order-consumer):
```text
seq=1 partition=2 offset=695 consumer=order-consumer-3
...
seq=10 partition=2 offset=704 consumer=order-consumer-3
```

## Những thứ phá vỡ ordering (dù đã dùng key)

| Nguyên nhân | Giải thích |
|---|---|
| Tăng số partition | mapping key → partition đổi; event cũ ở P1, event mới ở P4; hai consumer khác nhau xử lý song song |
| Retry topic | event 1 lỗi → sang `retry-orders`; event 2 thành công trên main topic → xử lý **trước** event 1 |
| Producer không idempotent + in-flight > 1 + retry | batch 2 thành công trước khi batch 1 retry |
| Consumer xử lý song song trong partition không theo key | thread pool không phân luồng theo key |
| Nhiều producer cho cùng key | không có thứ tự giữa 2 producer độc lập |
| Rebalance + không commit đúng | xử lý lại record cũ sau record mới (duplicate "quay ngược") |
| Key sai (vd key = user_id nhưng cần thứ tự theo order) | event của order nằm cùng partition nhưng xen lẫn, vẫn đúng; ngược lại key=order_id không cho thứ tự giữa các order của cùng user |

## Trade-off

- Ordering mạnh hơn = song song kém hơn. Thứ tự theo user + 1 user "whale" = hot partition (lab 12).
- Global ordering = 1 partition = 1 consumer → trần throughput thấp (performance A2: 1 partition = 380 rec/s với 1ms/record).
- Pattern thay thế: consumer chịu được out-of-order bằng **version/sequence** trong event (bỏ event có version cũ hơn state hiện tại) — order-consumer log `OUT OF ORDER sequence` khi phát hiện.

## INTERVIEW

1. Kafka đảm bảo ordering ở mức nào?
2. Làm sao đảm bảo các event của một order được xử lý theo thứ tự?
3. Retry topic ảnh hưởng ordering thế nào? Giải pháp? (retry giữ ordering = blocking retry, hoặc "park" cả key khi một event của key đang ở retry)
4. Vì sao không nên tăng partition cho topic cần ordering theo key?
