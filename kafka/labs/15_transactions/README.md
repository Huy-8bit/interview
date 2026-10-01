# Lab 15 — Transactions: consume → process → produce exactly-once

**Mục tiêu**: txn-processor đọc `txn-input` (read_committed), ghi `txn-output` + commit offset trong một transaction; abort một lần để thấy read_uncommitted vs read_committed và control marker.
**Đọc trước**: [docs/16](../../docs/16-transactions.md), [docs/14](../../docs/14-delivery-semantics.md)

## Chạy
```bash
./labs/15_transactions/run.sh
docker compose logs -f txn-processor | grep TXN
```

## Quan sát (kết quả thật)
```text
TXN COMMITTED orders=txn-...-a
TXN ABORTED: outputs invisible to read_committed, offsets rewound -> will reprocess orders=txn-...-b
TXN COMMITTED orders=txn-...-b ; TXN COMMITTED orders=txn-...-c
read_uncommitted sees 4 ; read_committed sees 3
txn-output log end offsets grew by 8 (4 data + 4 control marker)
| offset: 7 ... endTxnMarker: COMMIT coordinatorEpoch: 4      (+ một ABORT marker)
kafka-transactions describe: ProducerId 17005 ProducerEpoch 9 CompleteCommit
```
Ghi chú: franz-go bỏ record còn trong buffer khi abort; txn-processor `Flush()` trước khi abort để record bị abort thực sự nằm trên log.

## Câu hỏi
1. Vì sao offset không liên tục?
2. Processor crash giữa transaction thì sao?
3. Transaction có giúp gì cho việc gọi payment API không?
