# Eventual consistency như product contract

## Bài toán và ví dụ đầu tiên

Order DB đã commit nhưng trang search chưa thấy order vì index cập nhật qua event. Eventual consistency chấp nhận khoảng trễ giữa nguồn sự thật và projection, với điều kiện workflow delivery/retry/merge cuối cùng làm các view hội tụ.

## Đi từng bước qua một tình huống

API trả order ID và trạng thái accepted; UI có thể đọc nguồn chính cho order vừa tạo hoặc hiển thị pending indexing. Consumer nhận event, cập nhật index và lưu tiến trình. Nếu event lặp, update phải idempotent; nếu event đến ngược version, không được ghi state cũ lên state mới.

## Hiểu cơ chế từ kết quả quan sát

Hội tụ cần assumptions: event không mất vĩnh viễn, retries có thể tiến triển, poison record được xử lý và conflict có quy tắc. “Cuối cùng sẽ đúng” không đủ khi không có owner cho backlog/DLQ. Projection có thể rebuild từ source/log nếu retention và schema cho phép.

## Khái niệm và mô hình làm việc

Async projections hội tụ nếu delivery/retry/merge assumptions giữ; UI phải biểu diễn pending/stale states.

## Cơ chế và những ranh giới cần giữ

Version events theo aggregate, idempotent apply và reject stale updates; DLQ cần remediation để convergence thật.

## Áp dụng vào hệ thống thật

Order status trả pending kèm polling/notification; reconciliation so source với projection.

## Những đường lỗi cần hiểu

Event bị bỏ vĩnh viễn; retry reorder làm state lùi; UI tuyên bố final khi projection chưa apply.

## Lần theo bằng chứng khi có sự cố

Freshness lag theo wall time, version gaps và reconciliation mismatch counts.

## Đánh đổi và giới hạn sử dụng

Latency/availability tốt hơn nhưng client complexity và stale decisions tăng.

## Thực hành, debugging và kết luận

Đo freshness lag theo thời gian event và user-visible status. Test event delay, duplicate và reorder. Trade-off là read nhanh/decoupling đổi lấy UI trạng thái trung gian và vận hành repair; với invariant cần đọc mới ngay, chọn đường đọc thích hợp thay vì phủ mọi thứ bằng cache.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)
