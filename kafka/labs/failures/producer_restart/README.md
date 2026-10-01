# Failure: Producer restart: graceful vs crash

**Đọc**: [docs/15](../../../docs/15-idempotence.md), [docs/22 §8 outbox](../../../docs/22-system-design.md)

## Chạy
```bash
./labs/failures/producer_restart/run.sh
```

## Điều xảy ra
SIGTERM: flush buffer rồi thoát. SIGKILL: record đã Produce() nhưng chưa ack bị mất; restart → PID mới.

## Quan sát (kết quả thật khi xây lab)
```text
graceful shutdown flushed (failed=0) ; producerId 25002 -> 24007 ; SIGKILL: không có 'shutdown complete'
```

## Câu hỏi
Thiết kế producer không mất event khi bị kill -9?

Sau lab: `./scripts/reset-lab.sh`.
