# TLS: trust, identity và lifecycle

## Bài toán và ví dụ đầu tiên

Client cần biết nó đang nói với server đúng và dữ liệu không bị đọc/sửa trên đường truyền. TLS thiết lập kênh bảo vệ transport và kiểm tra peer theo certificate/trust policy, không xác thực quyền của user trong API.

## Đi từng bước qua một tình huống

HTTPS client kiểm tra certificate chain, hostname và thời hạn theo cấu hình. Tắt verification để chữa lỗi certificate làm mất bảo đảm identity quan trọng. mTLS thêm client certificate để service xác thực client identity, nhưng vẫn cần map identity đó thành quyền cụ thể.

## Hiểu cơ chế từ kết quả quan sát

TLS handshake có chi phí nên connection reuse giúp giảm overhead. Termination ở load balancer nghĩa đoạn phía sau có policy bảo vệ riêng. Rotation certificate/CA cần cửa sổ tương thích và reload/connection lifecycle đúng, không chỉ thay file rồi giả định mọi process dùng ngay.

## Khái niệm và mô hình làm việc

TLS bảo vệ transport confidentiality/integrity và server identity; mTLS thêm client certificate identity.

## Cơ chế và những ranh giới cần giữ

Verify chain/hostname và trusted roots; certificate rotation trước expiry; reuse connections nhưng có policy cho identity changes.

## Áp dụng vào hệ thống thật

Internal mTLS service identity map tới authorization policy, không chỉ trust mọi cert cùng CA.

## Những đường lỗi cần hiểu

InsecureSkipVerify bỏ identity check; missing CA in container; expired cert; clock skew.

## Lần theo bằng chứng khi có sự cố

Inspect handshake failures, chain/SAN/expiry, time sync và root bundle; never log private keys.

## Đánh đổi và giới hạn sử dụng

TLS termination edge đơn giản nhưng trust boundary phía sau cần explicit; mTLS thêm rotation operations.

## Thực hành, debugging và kết luận

Test bằng certificates thử cho hostname/expiry/trust mismatch và kiểm tra retry/cancellation. Quan sát handshake failures khác request status errors. Dùng cấu hình/library chuẩn được cập nhật, tránh tự thiết kế protocol hoặc cipher selection từ ví dụ không rõ version.


## Đọc tiếp

- [API security theo trust boundaries](../07-api-design/api-security.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://cheatsheetseries.owasp.org/)
