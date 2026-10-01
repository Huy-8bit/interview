# 14 — Delivery semantics: at-most-once, at-least-once, exactly-once

> Lab: [08_delivery_semantics](../labs/08_delivery_semantics), [15_transactions](../labs/15_transactions), [16_idempotent_producer](../labs/16_idempotent_producer)

Semantics là thuộc tính của **cả pipeline** (producer → Kafka → consumer → side effect), không phải của một config.

## At-most-once — "không bao giờ trùng, có thể mất"

```text
Consumer         poll(off 5684) ─► COMMIT 5685 ─► process ─✗ CRASH
Restart          committed = 5685 ─► record 5684 không bao giờ được xử lý => MẤT
```
Lab 08 B (`ORDER_COMMIT_MODE=before-process`, fault `crash_before_process`):
```text
COMMIT before processing (at-most-once)  consumer=order-consumer-2 records=1
LAB FAULT: simulated crash BEFORE processing  partition=1 offset=5684
lab:order:order-lab08-loss-...  =>   (rỗng: không có side effect nào, kể cả sau restart)
```
Phía producer: `acks=0`, hoặc không retry.
Dùng khi: metrics/telemetry mất chút không sao, cần latency thấp.

## At-least-once — "không mất, có thể trùng" (mặc định nên dùng)

```text
Consumer         poll(off 5521) ─► process (side effect!) ─✗ CRASH (chưa commit)
Restart          committed = 5521 ─► xử lý lại 5521 => TRÙNG
```
Lab 08 A (`manual` commit, fault `crash_after_process`):
```text
LAB FAULT: simulated crash AFTER processing, BEFORE offset commit  partition=2 offset=5521
DUPLICATE delivery detected: event already processed, side effect skipped  partition=2 offset=5521
lab:order:order-lab08-dup-...  =>  deliveries 2  reserved_qty 3
```
`deliveries` (side effect không idempotent) = 2; `reserved_qty` (idempotent theo event_id) = 3 = đúng một lần.

Producer: `acks=all` + retry. Retry có thể tạo duplicate → bật idempotent producer.

=> **At-least-once + idempotent consumer = effectively-once** cho side effect. Đây là pattern thực tế phổ biến nhất.

## Exactly-once (EOS) trong Kafka

Kafka có EOS **cho luồng read-process-write nằm hoàn toàn trong Kafka**:
1. **Idempotent producer**: không duplicate do retry (PID + sequence).
2. **Transactions**: output records + consumer offsets commit **nguyên tử**.
3. Consumer phía sau dùng `isolation.level=read_committed`.

```text
txn-processor (GroupTransactSession):
  poll txn-input ─► begin ─► produce txn-output ─► sendOffsetsToTransaction ─► commit
                         (crash/abort ở bất kỳ đâu => output vô hình với read_committed, offset không tiến)
```
Lab 15: input `b` mang fault `abort_txn` → lần 1 ABORT (output đã ghi xuống log), offsets rewind → lần 2 COMMIT:
```text
read_uncommitted: txn-output P1 @2 a, @4 b (aborted), @6 b, @8 c   -> 4 record
read_committed  : txn-output P1 @2 a,              @6 b, @8 c   -> 3 record (đúng 1 lần mỗi input)
```

## Exactly-once KHÔNG có nghĩa là...

```text
Kafka ──► Consumer ──► External Payment API (charge thẻ)
                 └──► crash trước khi commit offset/transaction
Restart: Kafka giao lại record (đúng theo EOS của Kafka) => API bị gọi LẦN 2 => trừ tiền 2 lần
```
Transaction của Kafka không bao trùm HTTP call, email, ghi DB ngoài. Cần:
- **Idempotency key** cho API ngoài (payment-consumer gửi `order_id` làm idempotency key; gateway giả lập trong Redis trả lại payment cũ: log `gateway idempotency key hit: order already charged, re-emitting same payment`).
- Hoặc ghi DB + offset trong **cùng một DB transaction** (lưu offset trong DB, không trong Kafka).
- Hoặc **outbox pattern** phía producer (ghi event vào bảng outbox cùng transaction nghiệp vụ, relay đọc outbox → Kafka).

## Bảng so sánh

| | At-most-once | At-least-once | Exactly-once (Kafka EOS) |
|---|---|---|---|
| Producer | acks=0/1, no retry | acks=all, retry, idempotent | idempotent + transactional.id |
| Consumer commit | trước xử lý | sau xử lý | trong transaction (sendOffsetsToTransaction) |
| Consumer đọc | — | — | read_committed |
| Mất | có | không | không |
| Trùng | không | có (cần idempotent consumer) | không (trong Kafka) |
| Chi phí | thấp nhất | thấp | cao hơn: commit marker, coordinator round-trips, latency ≥ transaction interval |
| Side effect ngoài Kafka | — | dedup bằng event_id | **vẫn** phải idempotent |

## INTERVIEW

1. Vẽ timeline gây mất message và gây duplicate.
2. "Exactly-once" của Kafka đảm bảo điều gì và không đảm bảo điều gì?
3. Thiết kế consumer gọi payment API không bị trừ tiền 2 lần.
4. Vì sao at-least-once + idempotent consumer thường được chọn thay vì transactions?
