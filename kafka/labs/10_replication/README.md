# Lab 10 — Replication, ISR, min.insync.replicas, acks, mất quorum

**Mục tiêu**: RF=3/min ISR=2/acks=all trong 3 tình huống: mất 1 broker; ISR còn 1; mất 2 node (mất KRaft quorum).
**Đọc trước**: [docs/11](../../docs/11-replication.md), [docs/12](../../docs/12-isr.md), [docs/03](../../docs/03-kraft.md)

## Chạy
```bash
./labs/10_replication/run.sh       # ~4 phút; luôn tự khôi phục broker (trap)
```
Bước 2 dùng `./scripts/net-fault.sh block-replication 2` (iptables trong network namespace của kafka-2: chặn kafka-2 fetch từ leader nhưng vẫn cho controller traffic) để ISR co mà quorum vẫn còn.

## Quan sát (kết quả thật)
```text
1. stop kafka-3:     Isr: 1,2 cho mọi partition ; acks=all -> produced
2. block kafka-2:    Partition 3 Leader 1 Isr: 1 Elr: 2     (chỉ partition có ghi mới bị shrink)
                     acks=all -> ERROR: records have timed out ...
                     broker kafka-1 answered NOT_ENOUGH_REPLICAS 6 times (client retry tới delivery timeout)
                     acks=1   -> produced ... (chỉ 1 bản sao)
3. stop kafka-2 nữa: ERROR: describe quorum: context deadline exceeded ; activecontrollercount 0
                     acks=1 -> produced ; acks=all -> timed out (ISR không shrink được khi không có controller)
4. restore:          ISR full again ; acks=all -> produced
```

## Bài học đã gặp khi xây lab
Trước khi gán IP tĩnh cho broker, sau bước 3 cluster **không hồi phục**: Docker cấp IP mới/hoán đổi khi container restart, kafka-1 giữ địa chỉ cũ và không theo kịp quorum (118 URP kéo dài). Fix: `ipv4_address` cố định (xem docs/21 mục 16).

## Câu hỏi
1. Vì sao ở bước 2 chỉ P3/P5 bị shrink ISR?
2. Vì sao client thấy "timed out" thay vì NOT_ENOUGH_REPLICAS?
3. Ở bước 3, vì sao acks=all không nhận được NOT_ENOUGH_REPLICAS?
