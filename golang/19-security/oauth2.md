# OAuth2, OIDC và authorization code flow

## Bài toán và ví dụ đầu tiên

Ứng dụng muốn truy cập tài nguyên thay mặt người dùng mà không giữ password của họ. OAuth 2 là framework ủy quyền; việc xác thực danh tính thường liên quan một protocol bổ sung như OpenID Connect theo triển khai.

## Đi từng bước qua một tình huống

Flow được chọn theo loại client và threat model; browser/public client có các yêu cầu khác backend confidential client. Redirect URI phải được kiểm soát, state/PKCE và token handling tuân protocol hiện hành của provider. Không dùng access token của một audience như chứng minh quyền ở mọi service.

## Hiểu cơ chế từ kết quả quan sát

Scopes biểu diễn quyền được cấp trong contract, không tự map đúng mọi resource ownership. Token expiry/refresh/rotation cần storage và concurrency policy để nhiều requests không refresh cùng lúc sai cách. Client secret không an toàn khi nhúng vào ứng dụng public có thể bị người dùng đọc.

## Khái niệm và mô hình làm việc

OAuth2 cấp delegated access; OIDC thêm identity layer. Flow choice phụ thuộc client type và threat model.

## Cơ chế và những ranh giới cần giữ

Authorization Code + PKCE, exact redirect URI validation, state/nonce theo protocol và secure token storage. Client credentials cho machine identity, không thay end-user consent.

## Áp dụng vào hệ thống thật

Backend validate tokens từ trusted issuer; refresh token rotation theo provider, secrets không nằm browser bundle.

## Những đường lỗi cần hiểu

Open redirect, stolen refresh token, confusing ID token với API access token, missing PKCE binding.

## Lần theo bằng chứng khi có sự cố

Review redirect registration, scopes/audience, callback correlation và token lifecycle; dùng provider-supported library.

## Đánh đổi và giới hạn sử dụng

Không tự viết OAuth server chỉ để interview demo; contract/provider security updates phải theo docs.

## Thực hành, debugging và kết luận

Test callback error, state mismatch, expiry và provider unavailable trên môi trường thử. Không log authorization code hoặc tokens. Khi triển khai thật, đối chiếu tài liệu provider/chuẩn hiện hành thay vì copy một flow cũ từ bài tổng quan.


## Đọc tiếp

- [API security theo trust boundaries](../07-api-design/api-security.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9700.html)
