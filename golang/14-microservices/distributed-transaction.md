# Distributed transactions và ownership

## Bài toán và ví dụ đầu tiên

Order đã commit ở DB A nhưng inventory reserve ở DB B thất bại. Transaction local không bao phủ cả hai chỉ vì code chạy trong một use case. Phải định nghĩa invariant nào cần atomic, invariant nào được hoàn thành qua workflow.

## Đi từng bước qua một tình huống

Nếu có thể đặt state cần atomic cùng một owner/DB, dùng local transaction thường đơn giản. Nếu buộc nhiều service, saga lưu progress và compensation; outbox nối local commit với event. Hai-phase commit có assumptions và availability/operational cost riêng, không là mặc định cho mọi HTTP service.

## Hiểu cơ chế từ kết quả quan sát

Pending và compensating là trạng thái nghiệp vụ thực, có thể sống qua process restart. Compensation có thể thất bại và không hoàn nguyên mọi external effect. Operation ID, dedup và authority/version giúp retries không tạo side effects mới ngoài ý định.

## Khái niệm và mô hình làm việc

Atomic commit qua nhiều services cần protocol/coordination; local sql.Tx không bao HTTP calls.

## Cơ chế và những ranh giới cần giữ

Ưu tiên local invariant+outbox; saga cho cross-service workflow có intermediate states và compensation. Two-phase commit có availability/operations trade-offs.

## Áp dụng vào hệ thống thật

Reserve inventory rồi authorize payment, persist saga progress và idempotent commands.

## Những đường lỗi cần hiểu

Timeout sau provider success; compensation fail; retry duplicate side effect.

## Lần theo bằng chứng khi có sự cố

Track saga state/age, command IDs và reconcile source systems.

## Đánh đổi và giới hạn sử dụng

Không tách một invariant mạnh qua services khi chưa có lý do và recovery design.

## Thực hành, debugging và kết luận

Test crash sau mỗi durable boundary và đối soát dữ liệu sau recovery. Khi incident, dừng retry mù với ID mới, tìm workflow state và provider references. Chọn thiết kế từ yêu cầu đúng đắn, tránh tách service rồi mới phát hiện invariant không chịu được trạng thái trung gian.


## Đọc tiếp

- [Microservices: independent ownership có chi phí](../11-software-architecture/microservices.md)
- [Distributed failure matrix](../12-distributed-systems/failure-scenarios.md)
- [tracing](../17-observability/tracing.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://grpc.io/docs/guides/)

## Thực hành có điều kiện kiểm chứng

Workflow order→inventory→payment phải ghi state sau mỗi local commit và dùng stable command IDs. Nếu payment timeout, compensation release stock ngay có thể sai khi charge đã xảy ra; chuyển unknown/reconcile theo product policy. Một saga state machine cần retry và compensation retry riêng, với alert cho stuck transitions chứ không chỉ request failure counters.
