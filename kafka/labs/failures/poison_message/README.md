# Failure: Poison message

**Đọc**: [docs/17](../../../docs/17-retry-dlq.md)

## Chạy
```bash
./labs/failures/poison_message/run.sh  (= labs/09_retry_dlq)
```

## Điều xảy ra
Record không thể xử lý → retry có giới hạn → DLQ; main topic không bị chặn.

## Quan sát (kết quả thật khi xây lab)
```text
attempt 1/3, 2/3, 3/3 (2s/4s/8s) → orders-dlq ; JSON hỏng → DLQ ngay
```

## Câu hỏi
Payment consumer chọn 'stop the line' thay vì DLQ — vì sao?

Sau lab: `./scripts/reset-lab.sh`.
