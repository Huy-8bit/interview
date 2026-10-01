# Lab 09 — Retry topic, DLQ, poison message, replay

**Mục tiêu**: theo dõi orders → retry-orders (×3, backoff 2s/4s/8s) → orders-dlq; lỗi không retry được → DLQ ngay; sửa nguyên nhân → replay thành công.
**Đọc trước**: [docs/17](../../docs/17-retry-dlq.md)

## Chạy
```bash
./labs/09_retry_dlq/run.sh
./scripts/replay-dlq.sh orders-dlq --dry-run       # công cụ dùng tay
docker compose exec toolbox kcli dlq-inspect -dlq orders-dlq
```

## Quan sát (kết quả thật)
```text
10:19:30.144 [orders P3@5834]       FAILED -> retry-orders (attempt 1/3, backoff 2s)
10:19:32.157 [retry-orders P0@0]    FAILED -> retry-orders (attempt 2/3, backoff 4s)
10:19:36.178 [retry-orders P0@1]    FAILED -> retry-orders (attempt 3/3, backoff 8s)
10:19:44.179 [retry-orders P0@2]    FAILED -> orders-dlq (retries exhausted after 4 attempt(s))
malformed JSON -> FAILED -> orders-dlq (non-retryable error after 1 attempt(s))
orders-dlq P2 @1 key=order-lab09-p777-...
    origin : orders/P5@5650  failed_group=order-processing-group-retry  attempts: 4
    error  : inventory service unavailable for product 777
replay ... -> retry-orders (replay #1)  -> processed ... deliveries=1
replay poison chưa sửa -> lại vào DLQ, "replayed: 1 time(s) before"
```

## Câu hỏi
1. Vì sao không retry vô hạn trên `orders`?
2. Event 1 của order X vào retry, event 2 thành công ngay — hậu quả? Cách khắc phục?
3. Vì sao replay mặc định vào `retry-orders` chứ không phải `orders`?
