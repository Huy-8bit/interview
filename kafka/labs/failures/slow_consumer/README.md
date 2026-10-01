# Failure: Slow consumer

**Đọc**: [docs/19](../../../docs/19-performance.md)

## Chạy
```bash
./labs/failures/slow_consumer/run.sh  (= labs/17_backpressure)
```

## Điều xảy ra
Consumer chậm → lag và end-to-end latency tăng; Kafka giữ dữ liệu.

## Quan sát (kết quả thật khi xây lab)
```text
lag 137k, e2e p95 53s, drain về 0 khi bỏ delay
```

## Câu hỏi
Khi nào slow consumer dẫn tới mất dữ liệu?

Sau lab: `./scripts/reset-lab.sh`.
