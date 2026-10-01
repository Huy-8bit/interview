# Lab 02 — Topic, partition, replica, file trên disk

**Mục tiêu**: thấy partition là gì về mặt vật lý: leader/replica/ISR, thư mục và segment trên từng broker, cấu trúc RecordBatch.
**Đọc trước**: [docs/04](../../docs/04-topic-partition.md), [docs/27](../../docs/27-log-storage.md)

## Chạy
```bash
./labs/02_partitions/run.sh
```

## Quan sát (kết quả thật)
```text
orders  0  kafka-1  kafka-1,kafka-2,kafka-3  kafka-1,kafka-2,kafka-3  11  OK
...      leaders per broker:  kafka-1=2  kafka-2=2  kafka-3=2
kafka-1: orders-0 orders-1 orders-2 orders-3 orders-4 orders-5        (RF=3 trên 3 broker: mỗi broker giữ mọi partition)
-rw-r--r-- 10485760 00000000000000000000.index      (pre-allocated)
-rw-r--r--   213484 00000000000000000000.log
-rw-r--r--      102 00000000000000000524.snapshot   (producer state cho idempotence)
P0 603 16.7% ... P5 606 16.7%   max/avg=1.06
baseOffset: 0 ... producerId: 2000 producerEpoch: 0 partitionLeaderEpoch: 3 isTransactional: false
| offset: 0 ... key: order-4f48ca4c2a78 payload: {"event_id":...}
kafka_server_replicamanager_partitioncount 118 ; open file handles of kafka-1 JVM: 335
```

## Câu hỏi
1. Vì sao `.index` 10MB trong khi `.log` chỉ 213KB?
2. `producerId`/`sequence` trong dump-log dùng để làm gì?
3. 118 partition replica trên một broker tốn những tài nguyên gì?
