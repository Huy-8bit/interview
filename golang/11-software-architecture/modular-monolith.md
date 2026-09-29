# Modular monolith

## Bài toán và ví dụ đầu tiên

Nhóm nhỏ cần domain boundaries nhưng chưa cần vận hành nhiều services. Modular monolith giữ một deployable trong khi chia code thành modules có API rõ, giúp transaction và debugging ban đầu đơn giản hơn.

## Đi từng bước qua một tình huống

Orders gọi inventory qua package contract thay vì truy cập trực tiếp mọi bảng/struct nội bộ. Một process có thể dùng một DB nhưng ownership schema và use case vẫn cần quy định. Dependency cycle giữa modules là tín hiệu phải xem lại orchestration hoặc boundary.

## Hiểu cơ chế từ kết quả quan sát

Monolith không đồng nghĩa mọi thứ global; microservices không tự tạo modularity. Giữ import rules và integration tests giúp module không biến thành thư mục hình thức. Khi tách service về sau, boundary đã rõ làm việc chuyển local call thành network call dễ xác định failure semantics hơn.

## Khái niệm và mô hình làm việc

Một deployable có domain boundaries rõ giúp tránh network/distributed transaction trước khi cần.

## Cơ chế và những ranh giới cần giữ

internal/user và internal/payment expose API nhỏ, tránh truy cập tables/state nhau tùy tiện; contracts có tests.

## Áp dụng vào hệ thống thật

Bắt đầu một binary, scale replicas; extract module khi workload/team autonomy chứng minh lợi ích.

## Những đường lỗi cần hiểu

Shared DB bị dùng làm backdoor qua module; package cycles; một global service phụ thuộc tất cả.

## Lần theo bằng chứng khi có sự cố

Import graph, ownership map và change lead time cho thấy coupling.

## Đánh đổi và giới hạn sử dụng

Deployment chung ít vận hành nhưng scale/failure isolation kém services độc lập.

## Thực hành, debugging và kết luận

Đo bottleneck/team ownership trước khi tách deploy. Một module cần scale riêng hoặc release độc lập có thể là ứng viên; chuyển qua mạng thêm timeout, idempotency và observability. Bắt đầu modular monolith thường hợp lý khi transaction và tốc độ học product quan trọng hơn isolation deploy.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Thực hành có điều kiện kiểm chứng

Architecture test/review có thể cấm payment import user storage adapter; payment chỉ dùng user public contract cần thiết. Một schema DB chung vẫn có table ownership và migrations owner. Khi extract module, đo cross-module queries/transactions trước: chúng là migration work thật, không biến mất chỉ vì tạo thêm binary hoặc repository.
