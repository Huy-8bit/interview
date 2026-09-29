# Leader election và epochs

## Bài toán và ví dụ đầu tiên

Nhiều replica chạy scheduler định kỳ nhưng chỉ muốn một replica phát job. Election chọn leader từ một authority nhất quán, thường dựa lease/quorum. Tuy nhiên thông báo mất leadership không tự dừng code ở process đang bị pause hoặc mất mạng.

## Đi từng bước qua một tình huống

A là leader rồi không renew được. B được bầu sau khi authority xác định lease hợp lệ của A hết. A có thể vẫn chạy loop cũ; mỗi hành động tạo durable effect cần epoch/fencing hoặc idempotent operation để stale leader không phá invariant. Stop signal trong process chỉ là một lớp phòng vệ.

## Hiểu cơ chế từ kết quả quan sát

Election giải quyết chọn coordinator, không tự replicate mọi state công việc. Lưu checkpoint/job identity bền để leader mới tiếp tục mà không mất hoặc phát trùng effect. Quorum loss có thể buộc ngừng nhận một số operation để giữ authority nhất quán theo design.

## Khái niệm và mô hình làm việc

Election chọn coordinator hiện tại theo authority; không tự dừng old leader ngoài mạng.

## Cơ chế và những ranh giới cần giữ

Lease/quorum service cấp leadership epoch; writes cần fencing hoặc compare-version tại resource. Renew loop có deadline và stop work khi mất quyền.

## Áp dụng vào hệ thống thật

Một scheduler tạo jobs với unique schedule+fire_time để duplicate leaders không double-create.

## Những đường lỗi cần hiểu

Network partition sinh two active actors; long pause làm expired owner wake.

## Lần theo bằng chứng khi có sự cố

Leadership transitions, lease age, epoch ở writes và rejected stale operations.

## Đánh đổi và giới hạn sử dụng

Leader giảm coordination trong work path nhưng là bottleneck/failover concern; partition ownership có thể tốt hơn.

## Thực hành, debugging và kết luận

Test kill, pause, partition và clock/lease timing trong môi trường kiểm soát. Log term/epoch và job IDs để nối timeline. Chỉ thêm leader khi thực sự cần singleton behavior; partitioned ownership hoặc DB claim job có thể đơn giản hơn một service election riêng.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://etcd.io/docs/v3.6/learning/api/)
