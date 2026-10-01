# Failure: Consumer crash

**Đọc**: [docs/09](../../../docs/09-rebalancing.md), [docs/14](../../../docs/14-delivery-semantics.md)

## Chạy
```bash
./labs/failures/consumer_crash/run.sh  (= lab 06 phần B + lab 08)
```

## Điều xảy ra
Phát hiện crash = session timeout; record xử lý dở → duplicate hoặc mất tuỳ thứ tự commit.

## Quan sát (kết quả thật khi xây lab)
```text
partitions re-assigned 10644 ms after the crash ; deliveries=2 (dup) ; lost khi commit trước
```

## Câu hỏi
Vì sao commit trong OnPartitionsLost là sai?

Sau lab: `./scripts/reset-lab.sh`.
