# Dead-letter queue như workflow vận hành

## Bài toán và ví dụ đầu tiên

Một record không xử lý được dù đã thử theo policy. Dead-letter queue, viết tắt DLQ, giữ record và thông tin lỗi để không chặn toàn pipeline, đồng thời không làm dữ liệu thất bại biến mất.

## Đi từng bước qua một tình huống

Record cần ID gốc, schema/version, timestamp và lý do phân loại; payload nhạy cảm phải giữ theo access/retention policy. Sau khi sửa lỗi, replay dùng cùng event identity và đi qua dedup. Copy record thành event mới có thể áp effect hai lần nếu lần cũ đã có partial outcome.

## Hiểu cơ chế từ kết quả quan sát

DLQ không tự là recovery. Nếu không có người sở hữu, alert theo tuổi và công cụ inspect/replay có kiểm soát, nó chỉ là backlog bị giấu. Bỏ một event khỏi stream có thể phá ordering hoặc invariant của events sau; cần ghi policy theo domain.

## Khái niệm và mô hình làm việc

DLQ giữ record không xử lý được cùng failure context để inspect/fix/replay.

## Cơ chế và những ranh giới cần giữ

Store original ID/payload schema/version, reason, attempts, first/last failure và source position; redact secrets và bound payload. Replay phải giữ idempotency identity.

## Áp dụng vào hệ thống thật

Schema mismatch quarantine rồi deploy converter và replay canary nhỏ trước batch.

## Những đường lỗi cần hiểu

DLQ không có owner/alert thành data loss im lặng; replay toàn bộ gây overload/duplicate.

## Lần theo bằng chứng khi có sự cố

Age/count by reason, sample payload safely, reconcile source to final effects.

## Đánh đổi và giới hạn sử dụng

DLQ tránh block stream nhưng không tự chữa dữ liệu; có retention và runbook.

## Thực hành, debugging và kết luận

Test poison record xen giữa hai event phụ thuộc và kiểm tra state cuối. Theo dõi ingress/egress DLQ, age và replay failures. Chỉ replay sau khi biết cause đã được sửa và downstream có capacity; một đợt replay lớn có thể tạo outage mới.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)

## Thực hành có điều kiện kiểm chứng

Replay drill: lấy10 records cùng một schema error, deploy transform fix, replay giữ original event ID và source metadata. Verify business effect count đúng, original DLQ item được đánh dấu resolved sau durable completion. Scale replay rate từ nhỏ; nếu dùng ID mới sẽ không kiểm chứng idempotency của original workflow. Dashboard phải có oldest unresolved age, không chỉ count.
