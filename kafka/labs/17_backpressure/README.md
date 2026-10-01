# Lab 17 — Backpressure: producer 5000 msg/s, consumer chậm

**Mục tiêu**: thấy Kafka dùng log làm buffer: lag tăng khi producer nhanh hơn consumer, giảm khi consumer bắt kịp.
**Đọc trước**: [docs/19](../../docs/19-performance.md), [docs/06](../../docs/06-consumer.md)

## Chạy
```bash
./labs/17_backpressure/run.sh                  # RATE=5000 SECS=30 DELAY_MS=5
```
Grafana > Consumer Lag và Consumer Performance (end-to-end latency) trong lúc chạy.

## Quan sát (kết quả thật)
```text
t=25s lag=126037  produce=5000/s  consume=405/s  e2e p95=29s
t=35s lag=135144  produce=1520/s  consume=415/s  e2e p95=53s
producer dừng: lag 132844 -> 126044 (drain ~430/s)
bỏ delay:      consume 1158 -> 2730 -> 3161 -> 2930 rec/s ; lag -> 0
```

## Câu hỏi
1. Vì sao consumer chỉ ~430/s dù delay 5ms × 6 partition ≈ 1000/s? (Redis + sync produce mỗi record)
2. Retention cần ≥ bao lâu để không mất dữ liệu trong kịch bản này?
