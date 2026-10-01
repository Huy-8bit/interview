# 15 — Idempotence: producer (PID/sequence) và consumer (event_id)

> Lab: [16_idempotent_producer](../labs/16_idempotent_producer), [08_delivery_semantics](../labs/08_delivery_semantics), [failures/producer_restart](../labs/failures/producer_restart)

## Phần 1 — Vì sao retry gây duplicate

```text
Producer ── Produce(batch #42) ──► Leader append (offset 900) ──► ProduceResponse ──✗ (mất / trễ quá request timeout)
Producer: "timeout, chắc chưa ghi" ── retry Produce(batch #42) ──► Leader append lần nữa (offset 901)
=> 2 bản sao
```
Lab 16 tái tạo đúng kịch bản: `tc netem` trễ **1500ms** gói tin từ leader về toolbox (response), client timeout 1s:
```text
A. idempotent=false   sent=400 failed=0   produce requests on the wire=171 batches acknowledged=170
                      records in topic for this run=401 distinct=400 DUPLICATES=1
B. idempotent=true    sent=400 failed=0   produce requests on the wire=163 batches acknowledged=158
                      records in topic for this run=400 distinct=400 DUPLICATES=0
```
Ở B có 5 request bị gửi lại, broker nhận ra là trùng và không ghi lần hai.

## Phần 2 — Idempotent producer hoạt động thế nào (internal)

1. Producer khởi động gửi `InitProducerId` → broker cấp **Producer ID (PID)** + **epoch** (lab dump-log: `producerId: 20001 producerEpoch: 0`).
2. Với mỗi (PID, partition), producer đánh **sequence number** tăng dần cho từng batch (`baseSequence`, `lastSequence`).
3. Leader lưu cho mỗi PID: sequence của **5 batch gần nhất** (producer state; snapshot ra file `*.snapshot` trong thư mục partition).
4. Batch tới:
   - `seq == last+1` → append.
   - `seq` trùng một batch đã có → **duplicate**: không append, trả về offset cũ như thành công.
   - `seq > last+1` → `OUT_OF_ORDER_SEQUENCE_NUMBER` (có lỗ: batch trước bị mất) → producer xử lý (reset).
5. Vì broker kiểm tra sequence, producer được phép có tới **5 request in-flight** mà không đảo thứ tự.

```text
kafka-dump-log idempotence-demo-0:
baseOffset: 559 lastOffset: 559 count: 1   baseSequence: 158 lastSequence: 158 producerId: 20001 producerEpoch: 0
baseOffset: 562 lastOffset: 800 count: 239 baseSequence: 161 lastSequence: 399 producerId: 20001 producerEpoch: 0
```

Điều kiện: `acks=all` (franz-go & Java bắt buộc), `max.in.flight ≤ 5`, retries > 0.

### Giới hạn quan trọng
- Chỉ chống trùng **trong một phiên producer** (một PID). Producer restart → **PID mới** (failures/producer_restart: `producerId 25002 → 24007`) → nếu ứng dụng *tự* gửi lại record cũ sau restart, broker coi là record mới.
- Chỉ chống trùng do **retry của client**. Nếu *ứng dụng* gọi Produce hai lần (vd retry HTTP request ở tầng trên), đó là hai record khác nhau.
- Muốn "PID bền qua restart" → `transactional.id` (transactions giữ PID, tăng epoch và fence instance cũ).

## Phần 3 — Idempotent consumer

> **Kafka idempotent producer ≠ business consumer tự động idempotent.**

Consumer vẫn nhận lại record sau crash/rebalance (at-least-once). Side effect phải chịu được:

| Kỹ thuật | Cách làm | Trong lab |
|---|---|---|
| Dedup table theo `event_id` | `INSERT processed(event_id)` cùng transaction với side effect | `store.ApplyOnce`: Lua script Redis `SET processed:<group>:<event_id> NX` + `HINCRBY` nguyên tử |
| Idempotency key cho API ngoài | gửi key cố định (order_id) — API trả kết quả cũ | payment-consumer → gateway giả lập (`lab:gateway:idem:<order_id>`) |
| Upsert / set state thay vì increment | `UPDATE ... SET status='PAID' WHERE version < x` | — |
| Deterministic output id | event phát ra lần 2 có cùng id → downstream dedup | `uuid.NewSHA1(eventID + "/payment")` |

Vì sao "đánh dấu đã xử lý" và "side effect" phải **nguyên tử**: tách rời thì crash ở giữa gây hoặc mất (mark trước, effect chưa) hoặc trùng (effect xong, mark chưa). Lab tách hai counter để thấy rõ: `deliveries` (không idempotent) = 2, `reserved_qty` (idempotent) đúng.

TTL của dedup store phải ≥ khoảng thời gian có thể replay (retention, DLQ replay...). Lab dùng 24h.

## INTERVIEW

1. Idempotent producer đảm bảo gì? PID/sequence/epoch làm gì?
2. Vì sao vẫn duplicate dù bật `enable.idempotence=true`? (restart, app-level resend, consumer redelivery)
3. Thiết kế idempotent consumer cho trừ tồn kho.
4. Vì sao bật idempotence vẫn giữ được ordering với 5 in-flight request?
