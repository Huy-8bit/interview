# Lab 12 — Hot key → hot partition

**Mục tiêu**: 80% record cùng key → một partition nhận phần lớn traffic → consumer sở hữu nó quá tải, consumer khác rảnh.
**Đọc trước**: [docs/19](../../docs/19-performance.md), [docs/21](../../docs/21-production-troubleshooting.md) mục 11

## Chạy
```bash
./labs/12_hot_partition/run.sh
./scripts/traffic.sh skewed 2000 60s 0.8 ; ./scripts/partition-stats.sh orders     # tay
```

## Quan sát (kết quả thật, 600 msg/s)
```text
uniform 20s:  P0..P5 ~16.6% mỗi partition, max/avg=1.03
skewed 30s:   P5 15021 83.5%  (các partition khác ~3.3%)  max/avg=5.01 <-- HOT PARTITION
lag:          orders 5 LAG 4753 (order-consumer-1) ; orders 0 LAG 122 (cùng consumer -> head-of-line) ; còn lại 0
rate:         P5 order-consumer-1 259.5 rec/s ; P1..P4 ~18 rec/s
salting 8 key order-HOT#0..7 -> chỉ rơi vào P1,P3,P4 (ít salt vẫn có thể lệch)
```

## Câu hỏi
1. Vì sao thêm consumer không giải quyết?
2. Vì sao P0 cũng bị lag?
3. Salting đánh đổi gì?
