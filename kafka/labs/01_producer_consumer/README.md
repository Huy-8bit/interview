# Lab 01 — Producer → Kafka → Consumer (theo dấu một message)

**Mục tiêu**: thấy một message đi từ HTTP API → producer → partition/offset trên broker → được 3 consumer group xử lý độc lập.
**Đọc trước**: [docs/01](../../docs/01-kafka-overview.md), [docs/05](../../docs/05-producer.md), [docs/06](../../docs/06-consumer.md)

## Chạy
```bash
./labs/01_producer_consumer/run.sh
```

## Làm tay
```bash
curl -s -XPOST localhost:8000/orders -d '{"user_id":1001,"product_id":500,"quantity":2}'          # sync, acks=all
curl -s -XPOST 'localhost:8000/orders?mode=async' -d '{"user_id":1002,"product_id":501,"quantity":1}'
docker compose logs -f order-consumer-1 order-consumer-2 order-consumer-3 | grep processed
docker compose exec toolbox kcli consume -topic orders -partition 5 -from 518 -max 1 -headers
```

## Quan sát (kết quả thật)
```text
{"event_id":"ff37db83-...","order_id":"order-1edb61a132ae","topic":"orders","key":"order-1edb61a132ae","partition":5,"offset":518,"acks":"all","mode":"sync","latency_ms":17.395}
producer-service  produced topic=orders partition=5 offset=518 key=order-1edb61a132ae acks=all latency=17.396ms
orders P5 @518 key=order-1edb61a132ae  header event_type=OrderCreated  header schema_version=1  header producer=producer-service
order-consumer-2  processed group=order-processing-group topic=orders partition=5 offset=518 key=order-1edb61a132ae hw=519 lag=0 took=8.17ms
payment-consumer  processed group=payment-group ... partition=5 offset=518                 (cùng record, group khác)
notification-consumer processed group=notification-group topic=payments ... event_type=PaymentSucceeded   (event phát sinh)
async: "partition": -1, "offset": -1 ... rồi log "produced (async ack) ... offset=550"
```

## Expected
5 EXPECT pass. Partition/offset trong response khớp log consumer. Async trả về trước khi có ack.

## Câu hỏi
1. `hw=519 lag=0` trong log consumer nghĩa là gì?
2. Vì sao payment-consumer cũng nhận record dù order-consumer đã xử lý?
3. Async produce thất bại thì client HTTP có biết không?
