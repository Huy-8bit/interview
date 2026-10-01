# Failure: Consumer rebalance

**Đọc**: [docs/09](../../../docs/09-rebalancing.md)

## Chạy
```bash
./labs/failures/consumer_rebalance/run.sh  (= labs/06_rebalancing)
```

## Điều xảy ra
Join/leave/crash → rebalance; eager vs cooperative vs KIP-848.

## Quan sát (kết quả thật khi xây lab)
```text
graceful 478ms, crash 10.6s, eager revoke tất cả, cooperative 0 revoke ở survivors
```

## Câu hỏi
Rebalance storm: nguyên nhân & cách xử lý?

Sau lab: `./scripts/reset-lab.sh`.
