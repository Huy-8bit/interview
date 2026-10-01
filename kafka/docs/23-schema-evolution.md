# 23 — Schema & schema evolution (Schema Registry)

> Lab: [19_schema_evolution](../labs/19_schema_evolution) · Schema Registry: http://localhost:8081

## WHAT

Kafka chỉ lưu **bytes**. Hợp đồng dữ liệu (schema) giữa producer và consumer phải được quản lý riêng. **Schema Registry** (Confluent) lưu schema theo **subject** (mặc định `<topic>-value` / `<topic>-key`), cấp **schema id** toàn cục, và **kiểm tra compatibility** khi đăng ký version mới. Bản thân dữ liệu registry nằm trong topic Kafka `_schemas` (compacted).

Wire format (lab 19 bước 7):
```text
[0x00 magic][4 byte schema id big-endian][payload Avro/Protobuf/JSON]
produced with schema id=3 (subject orders-sr-value v1): first bytes=00 00 00 00 03
```
Consumer đọc schema id → lấy schema từ registry (cache) → deserialize. Kafka UI làm đúng như vậy để hiển thị message.

## Các định dạng

| | JSON (không schema) | JSON Schema | Avro | Protobuf |
|---|---|---|---|---|
| Kích thước | lớn (tên field lặp) | lớn | nhỏ (binary, không tên field) | nhỏ |
| Schema bắt buộc khi đọc | không | có (validate) | **có** (writer schema) | có |
| Evolution rules | tự quản | phức tạp (open/closed content model) | rõ ràng, chuẩn nhất | field number |
| Lab | services dùng JSON + `schema_version` field | `orders-sr-value` | `orders-avro-value` (compat rules) | — |

## Compatibility modes

| Mode | Đảm bảo | Ai nâng cấp trước | Cho phép (Avro) |
|---|---|---|---|
| **BACKWARD** (mặc định) | consumer dùng schema MỚI đọc được dữ liệu CŨ | consumer trước | thêm field *có default*, xoá field |
| **FORWARD** | consumer dùng schema CŨ đọc được dữ liệu MỚI | producer trước | thêm field, xoá field *có default* |
| **FULL** | cả hai | thứ tự tuỳ ý | thêm/xoá field *có default* |
| `*_TRANSITIVE` | so với **mọi** version cũ, không chỉ version liền trước | | |
| NONE | không kiểm tra | | |

## Kết quả lab 19 (Avro, subject `orders-avro-value`)

```text
v1: order_id, user_id, product_id, quantity
v2: + coupon ["null","string"] default null      BACKWARD compatible? True   -> đăng ký version 2
v3: + currency string (KHÔNG default)            BACKWARD compatible? False
    reason: READER_FIELD_MISSING_DEFAULT_VALUE 'currency' ... has no default value and is missing in the old schema
v3: quantity int -> string                       BACKWARD compatible? False   reason: TYPE_MISMATCH
v3: xoá quantity                                 BACKWARD compatible? True
                                                 FORWARD compatible?  False   reason: READER_FIELD_MISSING_DEFAULT_VALUE 'quantity' (old schema)
                                                 FULL compatible?     False
```
Giải thích ví dụ "thêm currency không default" phá BACKWARD: consumer mới (reader schema v3) đọc record cũ (writer v2, không có currency) → không có giá trị nào để điền → lỗi.

## Quy trình evolution an toàn

1. Mọi field mới: **optional + default**.
2. Không đổi kiểu, không đổi tên (đổi tên = xoá + thêm; dùng alias trong Avro).
3. Xoá field: chỉ field có default (để FORWARD/FULL không vỡ).
4. Breaking change: topic mới (`orders.v2`), dual-write hoặc translator, migrate consumer, rồi bỏ topic cũ.
5. CI gọi `/compatibility/subjects/<s>/versions/latest` trước khi deploy.
6. Consumer phải chịu được field lạ (tolerant reader).

## JSON không schema registry (cách services trong lab làm)

Payload có `schema_version` + header `schema_version`; consumer bỏ qua field lạ (`encoding/json` mặc định), xử lý thiếu field bằng zero value + validate. Rẻ nhưng không có kiểm tra tự động — lỗi chỉ lộ ra khi chạy (thường thành poison message → DLQ).

## INTERVIEW

1. BACKWARD vs FORWARD vs FULL — ai được deploy trước trong mỗi mode?
2. Thêm field bắt buộc có an toàn không? Vì sao?
3. Schema id nằm ở đâu trong message?
4. Vì sao Avro/Protobuf hiệu quả hơn JSON trên Kafka?
