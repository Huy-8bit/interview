# Lab 04 — Ordering chỉ trong partition

**Mục tiêu**: chứng minh Kafka giữ thứ tự trong partition; không có global ordering; không key → mất thứ tự theo thực thể.
**Đọc trước**: [docs/10](../../docs/10-ordering.md)

## Chạy
```bash
./labs/04_ordering/run.sh
curl -s -XPOST 'localhost:8000/orders/order-xyz/events?count=10'   # tự thử
docker compose exec redis redis-cli LRANGE lab:seq:order-xyz 0 -1
```

## Quan sát (kết quả thật)
```text
WITH key:     order-52880-0  partitions=P5  IN ORDER  seq: 1(P5@355) 2(P5@356) ... 6(P5@360)
              consumer receive order: 1#1 1#2 ... 1#6 0#1 ... 2#6   (giữa các key: KHÔNG theo thứ tự gửi)
NO key + RR:  order-53098-0  partitions=P0,P3  OUT OF ORDER  seq: 1(P0@358) 3(P0@359) 5(P0@360) 2(P3@368) 4(P3@369) 6(P3@370)
NO key sticky: tất cả P2, "IN ORDER" — chỉ vì cả burst vào một batch
Pipeline: seq=1..10 partition=2 offset=695..704 consumer=order-consumer-3 (đúng thứ tự)
```

## Câu hỏi
1. Trong kết quả "WITH key", consumer nhận key-1 trước key-0 dù gửi xen kẽ — có vi phạm gì không?
2. Liệt kê 5 cách ordering bị phá dù dùng key.
