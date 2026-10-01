# 17 — Retry, Dead Letter Queue, Poison message, Replay

> Code: [pkg/kafka/consumer.go](../pkg/kafka/consumer.go) `routeFailure`, [tools/kcli/dlq.go](../tools/kcli/dlq.go) · Lab: [09_retry_dlq](../labs/09_retry_dlq)

## WHAT

- **Poison message**: record mà consumer không bao giờ xử lý được (sai schema, dữ liệu vô lý). Nếu retry vô hạn trên main topic → partition **kẹt** (mọi record phía sau chờ).
- **Retry topic**: chuyển record lỗi sang topic khác để main topic chạy tiếp; xử lý lại sau backoff.
- **DLQ**: nơi chứa record đã hết lượt retry hoặc lỗi không thể retry, chờ con người điều tra / replay.

## HOW — pipeline trong lab

```text
orders ──► order-processing-group (main runner)
             ├── OK  ──► commit
             └── lỗi ──► retry-orders  (attempt=1, retry_not_before=now+2s, headers metadata)  ──► commit
retry-orders ──► order-processing-group-retry (retry runner, cùng process, cùng handler)
             ├── chờ tới retry_not_before (backoff 2s, 4s, 8s)
             ├── OK  ──► commit
             ├── lỗi & attempt < 3 ──► retry-orders (attempt+1)
             └── lỗi & attempt = 3 hoặc lỗi permanent ──► orders-dlq
orders-dlq ──► kcli dlq-inspect / dlq-replay (mặc định replay vào retry-orders)
```

Headers mang theo (không sửa payload):
```text
retry_attempt  original_topic  original_partition  original_offset  original_timestamp
error  failed_at  failed_group  failed_by  retry_not_before  replayed_from_dlq  replay_count
```

Quy tắc an toàn: produce sang retry/DLQ là **sync, acks=all**, phải thành công trước khi commit offset gốc; không produce được sau 10 lần → **crash** (restart đọc lại từ committed offset) thay vì bỏ qua record. Bỏ qua im lặng = mất dữ liệu.

## Kết quả lab 09

A. Poison `quantity=-100`:
```text
10:19:30.144  [orders P3@5834]        FAILED -> retry-orders (attempt 1/3, backoff 2s)
10:19:32.157  [retry-orders P0@0]     FAILED -> retry-orders (attempt 2/3, backoff 4s)
10:19:36.178  [retry-orders P0@1]     FAILED -> retry-orders (attempt 3/3, backoff 8s)
10:19:44.179  [retry-orders P0@2]     FAILED -> orders-dlq (retries exhausted after 4 attempt(s))
```
B. JSON hỏng → `kafka.Permanent` → **DLQ ngay** (`non-retryable error after 1 attempt(s)`), 0 retry.
C. Lỗi tạm thời (inventory cho product 777 "down"): → DLQ; sửa dependency (`SREM lab:failing-products 777`); `kcli dlq-replay -key ...` → xử lý thành công:
```text
orders-dlq P2 @1 key=order-lab09-p777-...
    origin     : orders/P5@5650   failed_group=order-processing-group-retry failed_by=order-consumer-3
    attempts   : 4   failed_at=2026-10-01T10:17:54.580990111Z
    error      : inventory service unavailable for product 777
replay orders-dlq P2 @1 key=order-lab09-p777-... -> retry-orders (replay #1)
processed ... group=order-processing-group-retry topic=retry-orders ... key=order-lab09-p777-...
```
D. Replay poison chưa sửa → lại vào DLQ, header `replayed: 1 time(s) before` — replay không phải thuốc tiên.

## Phân loại lỗi

| Loại | Ví dụ | Xử lý |
|---|---|---|
| Transient | timeout DB, 503 API, rebalance | retry có backoff (inline vài lần, rồi retry topic) |
| Permanent / poison | parse lỗi, schema sai, vi phạm business rule | DLQ ngay (không tốn retry) |
| Bug của consumer | NPE với một dạng dữ liệu | DLQ → sửa code → replay |
| Hạ tầng sập toàn bộ | DB down 30 phút | **dừng consumer / pause** thay vì đẩy cả triệu record vào DLQ |

Lab cố ý cho `quantity<=0` đi đường retry (để quan sát pipeline); thực tế nên coi là permanent.

## Các chiến lược retry

| Chiến lược | Ưu | Nhược | Trong lab |
|---|---|---|---|
| Inline (blocking) retry | Giữ ordering | Chặn cả partition | payment-consumer `INLINE_RETRIES=3`, hết thì **crash (stop-the-line)** — thanh toán không được bỏ qua |
| Retry topic (non-blocking) | Main topic không kẹt | **Phá ordering** theo key; thêm topic | order-consumer |
| Nhiều tầng retry (`retry-5s`, `retry-1m`, `retry-10m`) | Backoff không chặn partition retry | Nhiều topic/consumer | doc |
| Retry topic + "park key" | Giữ ordering theo key | Cần state các key đang lỗi | doc |

Lưu ý thiết kế: **mỗi consumer group nên có retry/DLQ riêng** (`<group>.retry`, `<group>.dlq`). Lab dùng tên theo đề bài (`retry-orders` cho order-processing-group, `retry-payments`/`payments-dlq` cho notification-group). Replay mặc định vào **retry topic của group bị lỗi** thay vì topic gốc: replay vào `orders` sẽ khiến *mọi* group (payment, analytics...) nhận lại record → duplicate ở những nơi không hề lỗi.

## DLQ replay tool (`kcli dlq-replay`)

- Mặc định dùng group `dlq-replayer-<dlq>` → nhớ đã replay tới đâu, chạy lại không replay trùng.
- `-key K`: replay có lọc → **không ghi tiến độ** (nếu commit thì các record bị bỏ qua cũng bị đánh dấu đã replay — bug đã phát hiện và sửa khi làm lab).
- `-to retry|original|<topic>`, `-dry-run`, `-max N`.
- Reset attempt=0, thêm `replayed_from_dlq`, tăng `replay_count`.

## PRODUCTION

- Alert khi DLQ nhận record (`dlq_total` tăng) — DLQ không ai xem = mất dữ liệu có thủ tục.
- Retention DLQ dài hơn main topic (lab: 30 ngày).
- Payload DLQ có thể chứa PII → ACL chặt.
- Có runbook: inspect → phân loại → fix → replay → xác minh.

## INTERVIEW

1. Poison message là gì, vì sao không retry vô hạn trên main topic?
2. Retry topic ảnh hưởng ordering thế nào?
3. DLQ cần chứa metadata gì?
4. Replay DLQ vào topic gốc có vấn đề gì?
5. Khi nào nên dừng consumer thay vì đẩy vào DLQ?
