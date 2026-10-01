# Lab 08 — Delivery semantics với crash thật

**Mục tiêu**: tạo duplicate (at-least-once) và message loss (at-most-once) bằng crash thật (`os.Exit` trong consumer), và thấy idempotent consumer hấp thụ duplicate.
**Đọc trước**: [docs/14](../../docs/14-delivery-semantics.md), [docs/15](../../docs/15-idempotence.md)

## Cơ chế lab
- `kcli order -fault crash_after_process` / `crash_before_process`: consumer tự crash **một lần** cho event đó (Redis đánh dấu).
- Redis `lab:order:<id>`: `deliveries` (+1 mỗi lần giao — không idempotent), `reserved_qty` (áp dụng 1 lần theo event_id — idempotent).
- Phần B recreate consumer với `ORDER_COMMIT_MODE=before-process`, cuối lab trả về `manual`.

## Chạy
```bash
./labs/08_delivery_semantics/run.sh
```

## Quan sát (kết quả thật)
```text
A  LAB FAULT: simulated crash AFTER processing, BEFORE offset commit  partition=2 offset=5521
   DUPLICATE delivery detected: event already processed, side effect skipped  partition=2 offset=5521
   lab:order:order-lab08-dup-... => deliveries 2 reserved_qty 3
B  COMMIT before processing (at-most-once) records=1
   LAB FAULT: simulated crash BEFORE processing partition=1 offset=5684
   lab:order:order-lab08-loss-... =>        (không bao giờ được xử lý: LOST)
C  crash before processing (manual commit) -> processed sau restart, deliveries 1
```

## Câu hỏi
1. Vẽ timeline A và B.
2. Vì sao "mark processed" và side effect phải nguyên tử?
3. Những record khác trong cùng batch với record gây crash bị gì?
