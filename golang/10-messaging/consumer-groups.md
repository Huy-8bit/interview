# Consumer groups và rebalancing

## Bài toán và ví dụ đầu tiên

Analytics và email đều cần đọc OrderCreated nhưng không nên chia nhau làm mất dữ liệu của bên kia. Hai consumer groups có tiến trình độc lập; các members trong một group chia công việc của group đó.

## Đi từng bước qua một tình huống

Group A có ba members và ba partitions thì có thể mỗi member nhận một partition. Nếu một member rời, rebalance đổi ownership. Worker cũ cần ngừng nhận thêm, xử lý/cancel phần đang giữ theo protocol và tránh checkpoint vượt những record chưa hoàn tất.

## Hiểu cơ chế từ kết quả quan sát

Commit offset là lưu progress theo partition/group, không là ack business effect trong DB ngoài Kafka. Parallel processing cần track contiguous completion để không commit qua gap. Client library/group protocol có chi tiết khác nhau về polling và revocation; dùng đúng docs version đang chạy.

## Khái niệm và mô hình làm việc

Một consumer group chia ownership partitions; groups khác nhau có progress độc lập.

## Cơ chế và những ranh giới cần giữ

Active consumers hữu ích bị giới hạn bởi partitions theo protocol thông thường. Rebalance revoke ownership: stop dispatch, handle/drain in-flight và commit chỉ phần completed còn hợp lệ.

## Áp dụng vào hệ thống thật

Scale workers trong pod có per-partition sequencing hoặc bounded parallel processing với contiguous commit tracking.

## Những đường lỗi cần hiểu

Commit từ stale owner; long task vượt poll/liveness constraints; rebalance storm do scale liên tục.

## Lần theo bằng chứng khi có sự cố

Assignment churn, rebalance duration, partition lag và task duration distribution.

## Đánh đổi và giới hạn sử dụng

Nhiều consumers hơn partitions không thêm parallelism; tăng partitions có ordering/key mapping implications.

## Thực hành, debugging và kết luận

Khi lag tăng sau deploy, xem rebalance rate, time giữa poll, processing duration và downstream saturation. Thêm member chỉ giúp khi có partition để phân công và dependency còn capacity. Test rolling restart khi còn work để kiểm chứng replay/dedup.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)
