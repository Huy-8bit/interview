# Microservices: independent ownership có chi phí

## Bài toán và ví dụ đầu tiên

Hai team cần deploy và scale những domain khác nhau độc lập. Microservices tách process/deployment và data ownership, nhưng cũng biến lời gọi nội bộ đáng tin hơn thành network call có partial failure.

## Đi từng bước qua một tình huống

Tách inventory khỏi orders nghĩa là transaction ghi cả hai không còn là một SQL transaction đơn giản. API cần reservation identity, timeout và trạng thái pending; workflow xử lý compensate khi một bước lỗi. Nếu mọi change vẫn buộc deploy cả hai cùng lúc, lợi ích độc lập chưa đạt.

## Hiểu cơ chế từ kết quả quan sát

Boundary nên theo ownership và invariant, không chia mỗi database table thành một service. Shared DB writes giữa services giữ coupling ở schema và transaction dù network đã tách. Observability, config, rollout và on-call cost tăng theo số service và dependency edges.

## Khái niệm và mô hình làm việc

Service boundary mang network failures, version skew và independent deployment; cần lý do ngoài code size.

## Cơ chế và những ranh giới cần giữ

Tách theo business capability và data ownership; sync calls bounded deadlines, async events có replay/idempotency.

## Áp dụng vào hệ thống thật

Payment independent reliability/compliance lifecycle, order qua API/event contract.

## Những đường lỗi cần hiểu

Distributed monolith với synchronous call chain dài và shared DB writes.

## Lần theo bằng chứng khi có sự cố

Service graph, fan-out, deployment coupling và incident blast radius.

## Đánh đổi và giới hạn sử dụng

Không extract khi team chưa vận hành observability/on-call/versioning; modular monolith có thể đủ.

## Thực hành, debugging và kết luận

Dựng một failure timeline của từng call trước khi tách. Đo lý do cần scale/deploy riêng và năng lực vận hành. Giữ local module khi lợi ích chưa đủ; microservices là trade-off tổ chức/kỹ thuật, không là bước trưởng thành bắt buộc của mọi hệ thống.


## Đọc tiếp

- [Interfaces: behavior, representation và typed nil](../01-go-core/interfaces.md)
- [Transactions và short critical sections](../08-database/transactions.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/modules/layout)

## Thực hành có điều kiện kiểm chứng

Trước extract notification, đo deploy coupling, provider-specific scaling và incident blast radius. Nếu tách, cần durable outbox từ order, event schema version, idempotent delivery và dashboard oldest notification age. Nếu chưa có owners/on-call cho hai services, separation code trong monolith có thể đạt phần lớn lợi ích với ít failure paths hơn.
