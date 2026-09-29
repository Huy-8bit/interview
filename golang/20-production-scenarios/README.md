# Production Scenarios

Tập incident response với giả thuyết có thể bác bỏ.

## Reading map

| Bài | Ưu tiên |
|---|---|
| [API high latency](api-high-latency.md) | P1 |
| [DB pool exhausted](connection-pool-exhausted.md) | P1 |
| [Database query slowdown](database-slow.md) | P1 |
| [Duplicate business effect](duplicate-message.md) | P1 |
| [20,000 goroutines trong production](goroutine-leak.md) | P1 |
| [CPU95%, memory normal, RPS normal](high-cpu.md) | P1 |
| [Kafka consumer lag tăng](kafka-lag.md) | P1 |
| [Memory tăng liên tục](memory-growth.md) | P1 |
| [Production race/data corruption](race-condition.md) | P1 |
| [Redis unavailable và cache collapse](redis-down.md) | P1 |
| [Service outage: first15 minutes](service-outage.md) | P1 |
| [Traffic spike và load shedding](traffic-spike.md) | P1 |

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
