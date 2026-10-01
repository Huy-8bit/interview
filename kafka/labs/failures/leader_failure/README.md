# Failure: Leader crash (kill -9) dưới tải

**Đọc**: [docs/13](../../../docs/13-leader-election.md)

## Chạy
```bash
./labs/failures/leader_failure/run.sh  (= labs/11_broker_failure)
```

## Điều xảy ra
Leader không kịp chuyển giao; partition mất leader tới khi controller fence broker (broker.session.timeout.ms).

## Quan sát (kết quả thật khi xây lab)
```text
leader P0 đổi kafka-1→kafka-2 ở +9s, epoch 18→19 ; acked 11956 = appended 11956 ; failed 0
```

## Câu hỏi
Giảm thời gian failover bằng cách nào, đánh đổi gì?

Sau lab: `./scripts/reset-lab.sh`.
