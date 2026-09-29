# RabbitMQ acknowledgments và routing

## Bài toán và ví dụ đầu tiên

Một service muốn đưa job gửi email cho worker lấy xử lý rồi ack. RabbitMQ route message qua exchange tới queue theo binding; mental model task queue thường khác Kafka log với nhiều group replay độc lập.

## Đi từng bước qua một tình huống

Producer publish và dùng publisher confirms theo durability contract cần thiết. Consumer nhận, thực hiện effect rồi ack; nếu crash trước ack, message có thể được redeliver. Ack trước effect có thể làm mất việc khi crash. Provider idempotency hoặc consumer dedup xử lý duplicate delivery.

## Hiểu cơ chế từ kết quả quan sát

Prefetch giới hạn một phần số delivery chưa ack mà consumer giữ, giúp backpressure. Requeue ngay một poison message có thể tạo hot loop; dùng retry delay và dead-letter policy có giới hạn. Queue durability, message persistence và replication là các cấu hình khác nhau, cần đối chiếu loại queue/version.

## Khái niệm và mô hình làm việc

RabbitMQ broker route messages tới queues; ack xác nhận consumer đã xử lý theo application contract.

## Cơ chế và những ranh giới cần giữ

Manual ack sau durable effect; prefetch bound unacked delivery. Publisher confirm nói broker nhận theo queue durability config, khác consumer ack.

## Áp dụng vào hệ thống thật

Task queue với routing keys, retry delay và dead-letter policy; Go channel/connection recovery theo client contract.

## Những đường lỗi cần hiểu

Auto-ack trước work mất task khi crash; nack requeue ngay tạo poison-message loop.

## Lần theo bằng chứng khi có sự cố

Ready/unacked counts, redeliveries, consumer utilization và confirm latency.

## Đánh đổi và giới hạn sử dụng

Kafka hợp replay log; RabbitMQ hợp routing/task queue; quorum/durability settings cần explicit.

## Thực hành, debugging và kết luận

Đo ready/unacked counts, age, redelivery và processing duration. Test consumer crash sau effect trước ack và broker failure theo topology. Chọn RabbitMQ/Kafka từ routing, replay, ordering và vận hành cần thiết, không chỉ từ throughput quảng cáo.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rabbitmq.com/docs/confirms)
