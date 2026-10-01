# Failure: Planned broker shutdown (controlled shutdown) dưới tải

**Đọc**: [docs/13](../../../docs/13-leader-election.md)

## Chạy
```bash
./labs/failures/broker_failure/run.sh
```

## Điều xảy ra
SIGTERM → broker xin controller chuyển leadership trước khi tắt → client gần như không thấy lỗi.

## Quan sát (kết quả thật khi xây lab)
```text
acked=7996 failed=0 appended=7996 ; kafka-2 back in sync
```

## Câu hỏi
So với leader_failure (kill -9), vì sao controlled shutdown không gây gián đoạn ~9s?

Sau lab: `./scripts/reset-lab.sh`.
