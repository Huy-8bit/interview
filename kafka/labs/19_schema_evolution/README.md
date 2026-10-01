# Lab 19 — Schema evolution với Schema Registry

**Mục tiêu**: kiểm tra compatibility BACKWARD/FORWARD/FULL bằng Avro schema thật; xem wire format.
**Đọc trước**: [docs/23](../../docs/23-schema-evolution.md). Schema ở `schemas/`.

## Chạy
```bash
./labs/19_schema_evolution/run.sh
curl -s localhost:8081/subjects ; curl -s localhost:8081/subjects/orders-avro-value/versions
```

## Quan sát (kết quả thật)
```text
v2 + coupon (default null)       BACKWARD compatible? True
v3 + currency (no default)       BACKWARD compatible? False  READER_FIELD_MISSING_DEFAULT_VALUE
v3 quantity int->string          BACKWARD compatible? False  TYPE_MISMATCH
v3 remove quantity               BACKWARD True ; FORWARD False ; FULL False
produced with schema id=3 (subject orders-sr-value v1): first bytes=00 00 00 00 03
```
Mở Kafka UI > Topics > `orders-sr` > Messages: value được decode qua Schema Registry.

## Câu hỏi
1. BACKWARD: deploy consumer hay producer trước?
2. Làm sao thêm một field bắt buộc mà không phá consumer?
