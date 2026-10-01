# Failure: Replica out of sync

**Đọc**: [docs/12](../../../docs/12-isr.md)

## Chạy
```bash
./labs/failures/replica_out_of_sync/run.sh
```

## Điều xảy ra
Chặn kafka-3 fetch (iptables port 29092) → leaders loại kafka-3 khỏi ISR sau replica.lag.time.max.ms; ghi vẫn được (ISR 2 ≥ min 2); gỡ chặn → catch up → ISR expand.

## Quan sát (kết quả thật khi xây lab)
```text
ISR shrinks on kafka-1/kafka-2: 0 -> 17 ; acks=all -> produced ; kafka-3 caught up, ISR expanded
```

## Câu hỏi
Khác gì giữa follower bị loại khỏi ISR và broker bị fence?

Sau lab: `./scripts/reset-lab.sh`.
