# Event-driven Go service lifecycle

## Bài toán và ví dụ đầu tiên

Go consumer dễ viết một loop poll rồi go handle(record), nhưng cách đó có thể tạo vô hạn worker, commit sai offset và shutdown mất công việc. Event-driven vẫn cần owner rõ cho client, poll loop, workers và progress.

## Đi từng bước qua một tình huống

Poll loop nhận records rồi đưa vào queue có bound; workers xử lý với context; coordinator theo dõi completed offsets theo partition. Khi shutdown, ngừng nhận thêm theo protocol client, drain/cancel trong budget rồi commit phần an toàn và close client. Không để worker tùy ý commit offset lớn nhất của riêng nó.

## Hiểu cơ chế từ kết quả quan sát

Rebalance thay ownership partition nên in-flight work phải gắn assignment generation hoặc cơ chế client tương ứng. Callback và goroutine safety phụ thuộc library. Shared Go maps lưu progress cần đồng bộ; thread-safe broker client không làm map ứng dụng thread-safe.

## Khái niệm và mô hình làm việc

Event-driven code vẫn cần explicit owners cho client, poll loop, worker pool, checkpoint và shutdown.

## Cơ chế và những ranh giới cần giữ

Poll bounded batches, dispatch theo partition/order policy, context-aware processing, durable effect, commit contiguous progress. Không share unsafe client handles trái contract.

## Áp dụng vào hệ thống thật

Outbox relay publish stable event IDs; consumer service có service context tách HTTP request.

## Những đường lỗi cần hiểu

Background errors bị bỏ; Close broker trước workers commit; concurrent handler mutation không sync.

## Lần theo bằng chứng khi có sự cố

Trace links qua event headers, lag/age metrics và structured event ID logs sampled.

## Đánh đổi và giới hạn sử dụng

Async decoupling thêm eventual consistency và replay burden; synchronous path tốt cho immediate invariant.

## Thực hành, debugging và kết luận

Test duplicate, out-of-order completion, revoke khi đang xử lý và shutdown timeout. Metrics queue bytes/age, in-flight per partition và contiguous progress giúp phát hiện gap. Chọn concurrency theo downstream budget; Kafka backlog không phải giấy phép dùng mọi RAM để buffer local.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)
