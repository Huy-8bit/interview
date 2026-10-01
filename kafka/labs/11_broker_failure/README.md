# Lab 11 — Kill -9 leader khi đang có tải

**Mục tiêu**: 200 msg/s (acks=all, idempotent) + consumers đang chạy, SIGKILL broker leader của orders P0: quan sát election, ISR, producer retry, consumer recovery, không mất dữ liệu, broker quay lại & catch up, preferred leader.
**Đọc trước**: [docs/13](../../docs/13-leader-election.md), [docs/11](../../docs/11-replication.md)

## Chạy
```bash
./labs/11_broker_failure/run.sh          # RATE=500 ./labs/... để tăng tải
```

## Quan sát (kết quả thật)
```text
crash at 11:53:13 UTC (kafka-1)
+3s,+6s  orders 0  leader kafka-1  ISR 1,2,3  epoch 18      (chưa bị fence)
+9s      orders 0  leader kafka-2  replicas broker-1(DOWN),kafka-2,kafka-3  ISR kafka-2,kafka-3  epoch 19  UNDER-REPLICATED
order-consumer: REBALANCE partitions LOST ... group manage loop errored (coordinator trên kafka-1) -> rejoin
restart: [ReplicaFetcher replicaId=1, leaderId=2] Truncating partition ... -> ISR full
traffic: acknowledged/failed = 11956 0 ; records appended = 11956
P0 led by its preferred replica kafka-1 again ; leaders per broker: kafka-1=2 kafka-2=2 kafka-3=2
```

## Câu hỏi
1. Vì sao leader chưa đổi ở +6s?
2. Không mất, không trùng: nhờ những cơ chế nào?
3. Nếu dùng acks=1 thì kết quả có thể khác thế nào?
