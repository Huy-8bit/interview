# Duplicate delivery không đồng nghĩa producer bug

## Bài toán và ví dụ đầu tiên

Consumer đã ghi đơn vào DB nhưng process crash trước commit offset. Sau restart, broker gửi lại record. Duplicate là outcome dự kiến của cửa sổ failure này, không mặc nhiên là broker bị lỗi.

## Đi từng bước qua một tình huống

Event phải có identity ổn định qua retry. Consumer chèn event ID vào bảng processed cùng transaction với business update. Unique conflict cho biết event đã áp dụng; caller xử lý như replay hợp lệ theo contract. Nếu marker ghi trước effect bằng transaction khác, crash giữa hai bước có thể làm bỏ mất effect.

## Hiểu cơ chế từ kết quả quan sát

Dedup retention phải bao phủ replay window. Side effect ngoài DB như gửi email cần provider idempotency hoặc workflow có trạng thái riêng; một bảng dedup local không atomic với mạng. Hai payload khác nhau cùng event ID phải được nhận diện conflict/corruption theo policy.

## Khái niệm và mô hình làm việc

Producer retries, consumer crash/rebalance và network ambiguity đều có thể tạo duplicates.

## Cơ chế và những ranh giới cần giữ

Theo dõi message ID, business operation ID và delivery attempt riêng. Kafka idempotent producer giảm duplicates trong phạm vi protocol, không dedup arbitrary business replay.

## Áp dụng vào hệ thống thật

Notification dedup theo user/template/event; payment dedup theo stable operation key.

## Những đường lỗi cần hiểu

Gắn ID mới mỗi retry; dedup TTL ngắn hơn backlog; duplicate đang in-flight đồng thời.

## Lần theo bằng chứng khi có sự cố

Correlate IDs/offsets/commit timestamps, kiểm tra unique constraint và retention.

## Đánh đổi và giới hạn sử dụng

Không hứa exactly-once end-to-end khi external effect không nằm trong transaction.

## Thực hành, debugging và kết luận

Test duplicate concurrent, crash sau effect và replay sau deploy schema mới. Metrics dedup hits cho biết replay behavior nhưng tăng mạnh có thể báo rebalance hoặc producer retry. Giữ event ID và operation ID trong telemetry đã sanitize để nối attempts.


## Đọc tiếp

- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)
- [Worker pool và bounded concurrency](../04-concurrency/worker-pool.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kafka.apache.org/41/design/design/)

## Thực hành có điều kiện kiểm chứng

Đặt pause sau DB Commit và trước offset commit rồi kill consumer. Khi restart, cùng event phải tới handler nhưng unique processed_event + effect transaction khiến effect count không tăng. Lặp lại với hai consumers đồng thời tranh cùng business key. Dedup key scope consumer_name+event_id cho phép independent projections xử lý cùng event mà không chặn nhau.
