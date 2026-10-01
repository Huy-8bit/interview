# 16 — Kafka Transactions & Exactly-once

> Code: [services/txn-processor](../services/txn-processor/main.go) · Lab: [15_transactions](../labs/15_transactions)

## WHAT

Transaction cho phép một producer ghi vào **nhiều partition** (kể cả `__consumer_offsets`) một cách **nguyên tử**: tất cả visible hoặc không gì visible (với consumer `read_committed`). Đây là nền của read-process-write exactly-once (Kafka Streams `processing.guarantee=exactly_once_v2`).

## Các thành phần

| Thành phần | Vai trò |
|---|---|
| `transactional.id` | Định danh **bền** của producer logic (lab: `txn-processor-txn-processor-1`). Map tới PID cố định |
| Producer epoch | Tăng mỗi lần `InitProducerId` → instance cũ (zombie) dùng epoch thấp bị **fence** (`PRODUCER_FENCED`) |
| Transaction coordinator | Broker leader của partition `__transaction_state` mà `transactional.id` băm vào; giữ state machine của transaction |
| `__transaction_state` | Topic nội bộ (compacted) lưu trạng thái transaction (Ongoing, PrepareCommit, CompleteCommit, ...) |
| Control record (marker) | Record đặc biệt COMMIT/ABORT ghi vào **từng partition** tham gia |
| LSO (last stable offset) | Offset nhỏ nhất của transaction còn mở; consumer `read_committed` chỉ đọc tới LSO và lọc bỏ record của transaction bị abort |

## HOW — luồng read-process-write

```text
txn-processor                     Txn coordinator (kafka-2)         Partitions
  InitProducerId(txnId) ───────►  PID=17005, epoch++ (fence cũ)
  poll txn-input (read_committed)
  Begin
  Produce(txn-output P1) ── AddPartitionsToTxn ─► state Ongoing ──► txn-output-1: data (isTransactional=true)
  SendOffsetsToTxn(group, offsets) ──► AddOffsetsToTxn ──────────► __consumer_offsets: offset commit (chưa visible)
  End(commit)  ── EndTxn(COMMIT) ──► PrepareCommit (ghi __transaction_state)
                                     ghi COMMIT marker vào mọi partition tham gia
                                     CompleteCommit
```
Kafka 4.x dùng **transactions v2 (KIP-890)**: epoch được bump ở *mỗi* lần kết thúc transaction (lab thấy `producerEpoch` 7 → 8 → 9 qua từng transaction), server-side verification chống "hanging transaction".

## Kết quả lab 15

```text
TXN COMMITTED  orders=txn-...-a
TXN ABORTED: outputs invisible to read_committed, offsets rewound -> will reprocess   orders=txn-...-b
TXN COMMITTED  orders=txn-...-b
TXN COMMITTED  orders=txn-...-c

read_uncommitted sees 4 output record(s); read_committed sees 3

kafka-dump-log txn-output-1:
baseOffset: 6 ... producerId: 17005 producerEpoch: 7 isTransactional: true isControl: false   (data: b, lần 2)
| offset: 7 ... endTxnMarker: COMMIT coordinatorEpoch: 4                                     (control record)
... endTxnMarker: ABORT ...                                                                  (cho lần 1 của b)
```
Log end offset tăng **8** cho 3 record commit + 1 abort: 4 data + 4 marker. Offset của marker chiếm chỗ → offset có "lỗ" từ góc nhìn consumer.

`kafka-transactions describe`:
```text
CoordinatorId TransactionalId               ProducerId ProducerEpoch TransactionState TransactionTimeoutMs
2             txn-processor-txn-processor-1 17005      9             CompleteCommit   30000
```

**Bẫy đã gặp khi làm lab**: lần đầu, abort không để lại dấu vết gì trên log (read_uncommitted cũng chỉ thấy 3). Nguyên nhân: record của transaction còn nằm trong buffer client (linger) lúc gọi `End(TryAbort)` → franz-go bỏ chúng phía client, không gửi đi. Code hiện `Flush()` trước khi abort để lab quan sát được record bị abort.

## Failure behavior

| Sự cố | Kết quả |
|---|---|
| Processor crash giữa transaction | Coordinator abort khi hết `transaction.timeout.ms` hoặc khi instance mới InitProducerId (bump epoch) → input được xử lý lại, output cũ vô hình |
| Zombie (instance cũ sống lại sau GC dài) | Epoch cũ → `PRODUCER_FENCED`, không ghi được |
| Rebalance | GroupTransactSession abort transaction đang mở khi bị revoke |
| Consumer `read_uncommitted` | Thấy cả record bị abort (lab: 4 thay vì 3) |

## Performance / trade-off

- Mỗi transaction thêm round-trip tới coordinator + marker trên mỗi partition → gom nhiều record mỗi transaction (Kafka Streams commit mỗi 100ms).
- Consumer read_committed phải chờ LSO → transaction kéo dài = latency tăng cho *mọi* consumer read_committed của partition đó.
- Một transaction dài bị treo giữ LSO → consumer read_committed "đứng" (hanging transaction; công cụ `kafka-transactions find-hanging/abort`).

## EOS ≠ side effect ngoài Kafka

Xem [14-delivery-semantics](14-delivery-semantics.md): HTTP call, email, DB ngoài **không** nằm trong transaction. Dùng idempotency key / outbox / lưu offset cùng DB transaction.

## DEBUG

```bash
docker compose exec kafka-1 kt kafka-transactions --bootstrap-server kafka-1:29092 list
docker compose exec kafka-1 kt kafka-transactions --bootstrap-server kafka-1:29092 describe --transactional-id txn-processor-txn-processor-1
docker compose exec toolbox kcli consume -topic txn-output -isolation committed
docker compose logs -f txn-processor | grep TXN
```

## INTERVIEW

1. transactional.id, producer epoch, transaction coordinator, read_committed — mỗi cái làm gì?
2. Làm sao Kafka tránh zombie producer ghi dữ liệu?
3. Consumer offset được commit trong transaction thế nào?
4. Vì sao offset trong topic transactional không liên tục?
5. Khi nào KHÔNG nên dùng transactions?
