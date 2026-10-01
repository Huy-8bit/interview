# Lab 03 — Message key → partition

**Mục tiêu**: chứng minh `partition = murmur2(key) % N`, cùng key → cùng partition, key=null → sticky partitioner.
**Đọc trước**: [docs/04](../../docs/04-topic-partition.md), [docs/10](../../docs/10-ordering.md)

## Chạy
```bash
./labs/03_message_key/run.sh
docker compose exec toolbox kcli hash -partitions 6 order-100 my-key-1   # tự thử
```

## Quan sát (kết quả thật)
```text
order-100  murmur2=-955961047  &0x7fffffff=1191522601  %6 = P1  (franz-go: P1)
order-101 với 6 partition -> P4 ; với 12 partition -> P10      (thêm partition đổi mapping)
order-lab03 partitions: 0 0 0 0 0           = murmur2(order-lab03) % 6 = P0
user 4242 (3 order khác nhau, key=user_id): 3 3 3
null key, SYNC 2000 record : 2000 produce batches  map[0:319 1:362 2:332 3:341 4:318 5:328]
null key, ASYNC 2000 record: 1 produce batch        map[2:2000]
```

## Câu hỏi
1. key = order_id hay user_id: đánh đổi về ordering và hot partition?
2. Vì sao null key async lại dồn hết vào một partition? Lợi ích?
3. Điều gì xảy ra với ordering nếu tăng `orders` từ 6 lên 12 partition?
