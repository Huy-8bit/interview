# Message từ publish tới effect và replay

Một message có thể được xử lý rồi được gửi lại vì ack bị mất. Học partition/offset/group bằng timeline đó, sau đó nối consumer idempotency, ordering, retry và backpressure. Queue không tạo capacity vô hạn; success cần được định nghĩa ở durable effect, không chỉ broker đã nhận bytes.

## Bắt đầu và cách thực hành

Bắt đầu với [kafka](kafka.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Backpressure: 10k vào, 5k ra](backpressure.md) | P1 |
| [Consumer groups và rebalancing](consumer-groups.md) | P1 |
| [Dead-letter queue như workflow vận hành](dlq.md) | P1 |
| [Duplicate delivery không đồng nghĩa producer bug](duplicate-message.md) | P1 |
| [Event-driven Go service lifecycle](event-driven-go.md) | P1 |
| [Idempotent consumer transaction](idempotent-consumer.md) | P1 |
| [Kafka với Go: commit boundary](kafka.md) | P1 |
| [Ordering và contiguous commit](ordering.md) | P1 |
| [Partitions: ordering và scale unit](partitions.md) | P1 |
| [RabbitMQ acknowledgments và routing](rabbitmq.md) | P1 |
| [Message retries và poison data](retry.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
