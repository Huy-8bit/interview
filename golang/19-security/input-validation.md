# Input validation tại boundaries

## Bài toán và ví dụ đầu tiên

JSON decode thành công chỉ chứng minh payload hợp cú pháp và kiểu theo decoder, không chứng minh amount dương, date hợp lệ hoặc user có quyền dùng product đó. Validation có nhiều lớp với trách nhiệm khác nhau.

## Đi từng bước qua một tình huống

Boundary giới hạn bytes, số phần tử, field format và range. Service kiểm tra rule nghiệp vụ theo state; DB constraints giữ invariant trước concurrent writes. Validation ở UI giúp UX nhưng server vẫn phải kiểm tra vì client có thể gọi API trực tiếp.

## Hiểu cơ chế từ kết quả quan sát

User input vào SQL dùng parameters; input chọn identifier/path/URL cần allowlist hoặc parsing/policy tương ứng. Escape string chung không phù hợp mọi sink. Normalization cần định nghĩa trước so sánh uniqueness/authorization để không tạo nhiều biểu diễn cùng ý nghĩa.

## Khái niệm và mô hình làm việc

Validation kiểm shape, limits và business semantics; sanitization không thay parameterization/authorization.

## Cơ chế và những ranh giới cần giữ

Bound bytes trước decode, validate required/ranges/enums, normalize khi contract yêu cầu; distinguish absent/null/zero. SQL values parameterized; identifiers allowlisted.

## Áp dụng vào hệ thống thật

Pagination limit 1..100 và tenant scope; upload path không cho traversal sau canonicalization policy.

## Những đường lỗi cần hiểu

Integer overflow, deeply nested JSON, decompression bombs, Unicode normalization mismatch.

## Lần theo bằng chứng khi có sự cố

Fuzz parser/property tests với boundary sizes và malformed inputs; measure allocation amplification.

## Đánh đổi và giới hạn sử dụng

Strict unknown-field rejection có thể phá forward compatibility; quyết định theo API version policy.

## Thực hành, debugging và kết luận

Test zero, negative, overflow, Unicode và payload lớn theo use case. Error nói field/rule đủ client sửa nhưng tránh lộ state nhạy cảm. Đừng chỉ blacklist một vài chuỗi xấu; giới hạn dữ liệu được phép và tác dụng mà nó có thể tạo.


## Đọc tiếp

- [API security theo trust boundaries](../07-api-design/api-security.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://cheatsheetseries.owasp.org/)

## Thực hành có điều kiện kiểm chứng

Endpoint nhận limit parse int rồi check 1..100 trước allocate slice. JSON body bị MaxBytesReader bound trước decode, còn decompressed stream cần limit ở đúng tầng giải nén. Patch API phân biệt missing/null/zero theo contract; pointer DTO đơn thuần có thể chưa đủ cả ba trạng thái. Fuzz malformed UTF-8, nested inputs và numeric extremes theo accepted schema.
