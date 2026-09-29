# Distributed failure matrix

## Bài toán và ví dụ đầu tiên

Một request thành công ở server nhưng client nhận lỗi; một message được xử lý nhưng ack mất; một cache trả dữ liệu cũ sau update. Những tình huống này là đường chạy bình thường phải thiết kế, không phải ngoại lệ hiếm có thể bỏ qua.

## Đi từng bước qua một tình huống

Đặt điểm crash trước durable commit, sau commit trước ack và sau ack. Ở mỗi điểm, xác định state còn lại sau restart và actor nào retry. Nếu không có operation ID hoặc durable progress, hệ thống khó phân biệt “chưa làm” và “đã làm nhưng chưa báo”.

## Hiểu cơ chế từ kết quả quan sát

Fault injection nên có mục tiêu: delay/drop response, duplicate event, pause consumer hoặc cắt một dependency. Kiểm tra invariant và recovery thay vì chỉ process restart được. Timeout/circuit breaker cải thiện kiểm soát tài nguyên nhưng không tự sửa duplicate side effect hay mất outbox.

## Khái niệm và mô hình làm việc

Mỗi network boundary có thể delay, drop, duplicate, reorder hoặc trả success nhưng response mất.

## Cơ chế và những ranh giới cần giữ

Vẽ commit point rồi đặt crash trước/sau mỗi step; định nghĩa safety và liveness riêng, cùng recovery owner.

## Áp dụng vào hệ thống thật

DB commit→outbox relay→consumer DB→offset commit có ít nhất ba replay boundaries.

## Những đường lỗi cần hiểu

DNS outage, partition, clock skew, dependency overload, stale leader, poisoned event và regional loss.

## Lần theo bằng chứng khi có sự cố

Timeline theo operation/event IDs, durable states và attempts; tránh kết luận từ log absence.

## Đánh đổi và giới hạn sử dụng

Fail closed bảo vệ invariant nhưng giảm availability; stale fallback cần product approval ở design time.

## Thực hành, debugging và kết luận

Bắt đầu ở staging với phạm vi và rollback rõ, dùng dữ liệu thử. Khi incident thật, ưu tiên hạn chế khuếch đại như retry storm, lưu bằng chứng và đối soát state trước replay. Runbook phải chỉ owner và điều kiện xác nhận phục hồi về cả SLO lẫn dữ liệu.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)
