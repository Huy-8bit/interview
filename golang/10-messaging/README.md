# Messaging

Delivery, ordering, replay và backpressure trong Go consumers.

## Reading map

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

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
