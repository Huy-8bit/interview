# Lab 06 — Rebalancing

**Mục tiêu**: đo rebalance khi consumer rời sạch vs crash; so sánh eager (range), cooperative-sticky, KIP-848.
**Đọc trước**: [docs/09](../../docs/09-rebalancing.md), [docs/07](../../docs/07-consumer-group.md)

## Chạy
```bash
./labs/06_rebalancing/run.sh             # A..E, ~5 phút
PARTS="A B" ./labs/06_rebalancing/run.sh # chỉ graceful vs crash
```
Phần C/D/E recreate order-consumer với `ORDER_BALANCER` / `ORDER_GROUP_PROTOCOL` khác nhau và tự trả về mặc định.

## Quan sát (kết quả thật, traffic 50 msg/s)
```text
A  graceful stop  -> orphaned partitions re-assigned 478 ms after docker stop
B  kill -9        -> +5s: order-consumer-2 vẫn sở hữu P3 (lag 46), P5 (lag 49)
                     partitions re-assigned 10644 ms after the crash  (session.timeout.ms=10s)
A2 join lại (cooperative): vòng 1 consumer-1 revoked=orders[P3], consumer-3 revoked=orders[P5]; vòng 2 consumer-2 assigned "orders[P3 P5]"
C  range (eager):  consumer-1 revoked="orders[P0 P1]" -> assigned "orders[P0 P1 P2]"  (mất cả phần của mình)
D  cooperative:    survivors revoked nothing (0 non-empty revokes)
E  KIP-848:        protocol=consumer (KIP-848) assignor=range ; incremental: revoked=orders[P2] -> assigned orders[P4 P5]
```

## Câu hỏi
1. Vì sao crash phát hiện chậm hơn graceful? Giảm thời gian đó bằng cách nào và đánh đổi gì?
2. Trong 10.6s sau crash, record của P3/P5 bị gì?
3. Eager vs cooperative ảnh hưởng gì tới consumer có state lớn?
