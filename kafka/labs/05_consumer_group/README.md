# Lab 05 — Consumer group: chia partition, consumer dư, nhiều group

**Mục tiêu**: thấy assignment thật; 8 consumer cho 6 partition → 2 idle; 3 group nhận cùng một record.
**Đọc trước**: [docs/07](../../docs/07-consumer-group.md)

## Chạy
```bash
./labs/05_consumer_group/run.sh
# tay:
docker compose --profile scale up -d          # order-consumer-4..8
docker compose exec toolbox kcli group -group order-processing-group -watch 2s
```

## Quan sát (kết quả thật)
```text
3 instance: order-consumer-1 orders[P0 P4] | order-consumer-2 orders[P1 P5] | order-consumer-3 orders[P2 P3]
8 instance: ... order-consumer-6 (none) <-- IDLE member ; order-consumer-7 (none) <-- IDLE member
cooperative-sticky: consumer-1 "revoked=orders[P4] still_owns=orders[P0]" rồi consumer-8 "newly_assigned=orders[P4]"
1 record (partition=0 offset=856) -> order-processing-group, payment-group, notification-group mỗi group 1 lần
```

## Reset
`./scripts/reset-lab.sh` dừng order-consumer-4..8.

## Câu hỏi
1. Consumer idle có ích gì?
2. Thêm group mới có làm chậm group cũ không?
3. Ai quyết định assignment (classic protocol)?
