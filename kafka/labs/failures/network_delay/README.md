# Failure: Network delay trên một broker

**Đọc**: [docs/11](../../../docs/11-replication.md), [docs/21 §9](../../../docs/21-production-troubleshooting.md)

## Chạy
```bash
./labs/failures/network_delay/run.sh
```

## Điều xảy ra
`tc netem delay 200ms` trên mọi gói rời kafka-1 → replication và response chậm → acks=all latency tăng; ISR không đổi vì follower vẫn theo kịp trong 10s.

## Quan sát (kết quả thật khi xây lab)
```text
produce p99 0.022s → 2.485s → 0.022s sau khi gỡ
```

## Câu hỏi
Metric broker nào tách được thời gian 'chờ follower' khỏi thời gian ghi disk?

Sau lab: `./scripts/reset-lab.sh`.
