# Lab 16 — Idempotent producer chống duplicate do retry

**Mục tiêu**: tạo "ack bị mất" bằng tc netem (response từ leader trễ 1.5s > timeout 1s của client) → retry → duplicate khi tắt idempotence, không duplicate khi bật.
**Đọc trước**: [docs/15](../../docs/15-idempotence.md)

## Chạy
```bash
./labs/16_idempotent_producer/run.sh
```

## Quan sát (kết quả thật)
```text
A idempotent=false: requests on the wire=171, batches acked=170 ; records in topic=401 distinct=400 DUPLICATES=1
B idempotent=true:  requests on the wire=163, batches acked=158 ; records in topic=400 distinct=400 DUPLICATES=0
dump-log: baseSequence: 161 lastSequence: 399 producerId: 20001 producerEpoch: 0
```
Số duplicate phụ thuộc thời điểm; điều quan trọng: A có thể > 0, B luôn 0.

## Câu hỏi
1. Broker nhận ra batch trùng bằng gì?
2. Producer restart rồi gửi lại record cũ — broker có loại không?
