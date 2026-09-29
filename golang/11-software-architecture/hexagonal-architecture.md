# Ports và adapters

## Bài toán và ví dụ đầu tiên

Một use case tạo order có thể được gọi từ HTTP và từ message consumer. Hexagonal architecture nhìn các điểm vào/ra như ports và adapters để core use case không bị gắn vào một transport.

## Đi từng bước qua một tình huống

Inbound adapter decode request/event rồi gọi cùng use case có input rõ. Outbound port mô tả việc lưu order hoặc charge; SQL/provider client là adapters. Context và operation ID đi xuyên boundary theo lifetime, còn auth/payload parsing ở đúng adapter.

## Hiểu cơ chế từ kết quả quan sát

Ports là contract hành vi, không chỉ chữ ký method. Store.Save phải nói transaction, duplicate và ownership; fake trong unit test phải giữ semantics quan trọng. Một adapter có thể map lỗi driver sang lỗi domain ổn định mà không làm mất thông tin debug nội bộ.

## Khái niệm và mô hình làm việc

Port là contract tại boundary; adapter chuyển protocol/infrastructure sang contract đó.

## Cơ chế và những ranh giới cần giữ

Inbound HTTP/gRPC gọi use case; outbound SQL/provider implement interface do consumer định nghĩa. Constructor nối concrete adapters.

## Áp dụng vào hệ thống thật

Payment gateway adapter chuyển vendor status sang domain result có ambiguous outcome rõ.

## Những đường lỗi cần hiểu

Vendor error/type rò qua domain; mocks chỉ mô phỏng implementation thay contract.

## Lần theo bằng chứng khi có sự cố

Contract tests chạy cùng cases cho adapter fake/real khi thích hợp.

## Đánh đổi và giới hạn sử dụng

Ports quá nhỏ/không có substitution làm ceremony; chọn boundary theo volatility.

## Thực hành, debugging và kết luận

Test core logic độc lập rồi contract/integration test adapters. Nếu chỉ đổi tên folders thành ports/adapters nhưng core vẫn gọi global DB, boundary chưa được tách. Dùng mô hình khi nhiều đầu vào/ra hoặc yêu cầu test isolation biện minh chi phí mapping.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Thực hành có điều kiện kiểm chứng

Port PaymentAuthorizer nên diễn tả Authorize(ctx, operationID, amount) và outcome confirmed/unknown/rejected theo domain. Nếu port trả raw vendor response và HTTP status, domain vẫn coupled vendor dù interface tồn tại. Adapter chịu mapping, deadline propagation và error wrapping. Contract test phải có timeout-after-effect case vì fake luôn trả success không kiểm recovery behavior.
