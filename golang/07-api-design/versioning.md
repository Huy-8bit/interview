# API versioning và compatibility

## Bài toán và ví dụ đầu tiên

Mobile client cũ tồn tại nhiều tháng sau khi server deploy. Đổi field amount từ integer sang string ngay lập tức có thể làm client lỗi dù server build/test mới đều pass. Versioning quản lý sự thay đổi contract giữa những bên không deploy đồng thời.

## Đi từng bước qua một tình huống

Thêm optional field thường dễ hơn xóa/đổi ý nghĩa field cũ, nhưng client parse strict có thể vẫn bị ảnh hưởng. Với thay đổi không tương thích, dùng version boundary rõ và migration window. Deprecation cần telemetry biết client nào còn dùng, thời hạn và fallback.

## Hiểu cơ chế từ kết quả quan sát

Tương thích gồm wire shape và semantics: field giữ nguyên type nhưng đổi timezone hoặc units vẫn là breaking change. Error codes, pagination order và default behavior cũng thuộc contract. Database schema evolution phía server cần expand/contract để code cũ/mới cùng chạy trong rollout.

## Khái niệm và mô hình làm việc

Version tồn tại ở wire shape lẫn semantics; additive change vẫn có thể phá strict clients.

## Cơ chế và những ranh giới cần giữ

Expand-contract: thêm optional field, deploy readers hiểu cả cũ/mới, migrate writers, đo adoption rồi deprecate. Enum thêm giá trị cần unknown handling.

## Áp dụng vào hệ thống thật

Version header/path theo ecosystem; có sunset policy và compatibility tests.

## Những đường lỗi cần hiểu

Required field mới phá old clients; rename mang ý nghĩa khác nhưng giữ route; generated clients reject enum lạ.

## Lần theo bằng chứng khi có sự cố

Replay fixtures và inspect client versions/errors; canary schema changes.

## Đánh đổi và giới hạn sử dụng

Giữ nhiều versions tăng maintenance; version chỉ khi contract break cần thiết.

## Thực hành, debugging và kết luận

Dùng contract fixtures của client cũ và test responses thực, không chỉ unit test handler mới. Theo dõi usage theo version với cardinality hữu hạn. Tránh tạo version mới cho mọi refactor nội bộ không đổi contract; giữ versioning cho thay đổi client quan sát được.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9110)
