# Vulnerabilities trong Go backend

## Bài toán và ví dụ đầu tiên

Nhiều lỗi backend xuất phát từ việc dữ liệu không tin cậy đi qua một boundary mà thiếu policy. SQL injection, SSRF, path traversal và broken object authorization khác cơ chế nhưng cùng đòi biết input được dùng để làm gì.

## Đi từng bước qua một tình huống

SQL dùng parameterized query; URL fetch kiểm soát destinations/redirects theo use case; file path giới hạn vùng truy cập; resource ID phải được kiểm tra quyền theo identity. Chỉ kiểm tra input là string không bảo đảm bất kỳ điều nào trong số đó.

## Hiểu cơ chế từ kết quả quan sát

Go memory safety loại bỏ một số lỗi memory thông thường nhưng không loại bỏ logic/auth/resource-exhaustion bugs. Unbounded body, goroutine hoặc decompression có thể cạn tài nguyên. Dependency vulnerabilities còn cần cập nhật và inventory phù hợp, không tự biến mất vì binary static.

## Khái niệm và mô hình làm việc

Memory safety giảm một lớp lỗi nhưng không ngăn injection, authorization bugs, SSRF hoặc resource exhaustion.

## Cơ chế và những ranh giới cần giữ

Review SQL/command construction, template context escaping, unsafe/cgo, dependency vulnerabilities, file path/URL trust và concurrency lifetime.

## Áp dụng vào hệ thống thật

Use govulncheck khi tool/version/network đã chuẩn bị, patch dependencies và verify reachability/behavior.

## Những đường lỗi cần hiểu

exec shell string từ input, arbitrary URL fetch, public debug listener, unbounded goroutines.

## Lần theo bằng chứng khi có sự cố

Threat-model data flow từ untrusted input tới sink; targeted negative tests và audit dependency versions.

## Đánh đổi và giới hạn sử dụng

Không coi static scan pass là secure; business authorization cần manual review/tests.

## Thực hành, debugging và kết luận

Thiết kế negative tests tại boundary và dùng dữ liệu thử trong môi trường sở hữu. Đo reject lý do và kiểm tra redaction. Ưu tiên controls theo khả năng tiếp cận và ảnh hưởng thật, tránh coi một checklist chung là bằng chứng endpoint đã an toàn.


## Đọc tiếp

- [API security theo trust boundaries](../07-api-design/api-security.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://cheatsheetseries.owasp.org/)
