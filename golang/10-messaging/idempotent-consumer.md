# Idempotent consumer transaction

## Bài toán và ví dụ đầu tiên

Một event cộng 100 điểm vào ví user. Nếu replay cộng thêm lần nữa, at-least-once delivery trở thành lỗi dữ liệu. Idempotent consumer làm nhiều lần nhận cùng event tạo effect tương đương một lần.

## Đi từng bước qua một tình huống

Trong cùng transaction, insert processed(event_id) có unique constraint rồi update points. Nếu insert trùng, biết lần trước đã commit cả marker và update; nếu transaction lỗi thì cả hai rollback để retry được. Tránh check tồn tại rồi update qua hai transaction vì hai consumer có thể cùng vượt check.

## Hiểu cơ chế từ kết quả quan sát

Ngoài identity cần version payload và phạm vi dedup theo consumer effect. Hai nhóm nghiệp vụ khác nhau có thể cần áp dụng cùng event độc lập. Lưu marker vô hạn có storage cost; xóa quá sớm phá replay semantics, nên retention gắn với log/retry contract và khả năng rebuild.

## Khái niệm và mô hình làm việc

Dedup record và business effect phải atomic trong cùng durable boundary để replay không double-apply.

## Cơ chế và những ranh giới cần giữ

INSERT processed_events(event_id) với unique key rồi mutation trong cùng transaction; duplicate no-op, commit rồi ack/offset. Retention dài hơn replay horizon.

## Áp dụng vào hệ thống thật

Ledger event có unique event ID; outbox từ transaction phát downstream event.

## Những đường lỗi cần hiểu

Mark processed trước effect nhưng khác transaction làm mất effect; effect trước dedup khác transaction làm duplicate.

## Lần theo bằng chứng khi có sự cố

Crash injection quanh begin/dedup/effect/commit/ack; reconcile expected state.

## Đánh đổi và giới hạn sử dụng

Dedup store tốn space; business natural idempotency như versioned upsert có thể đơn giản hơn.

## Thực hành, debugging và kết luận

Fault-inject trước commit, sau commit trước ack và concurrent delivery. Với HTTP effect bên ngoài transaction, dùng provider key và pending/reconcile workflow; không gọi local dedup là exactly-once toàn hệ thống. Quan sát duplicate rate cùng final business invariant.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)
