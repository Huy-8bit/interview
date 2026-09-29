# JWT validation và key rotation

## Bài toán và ví dụ đầu tiên

JWT là định dạng token có claims, thường được ký để verifier kiểm tra tính toàn vẹn. Decode base64 thành JSON không chứng minh chữ ký hợp lệ, và chữ ký hợp lệ chưa đủ nếu token không dành cho service này.

## Đi từng bước qua một tình huống

Verifier cần algorithm/key policy, signature verification và kiểm tra issuer, audience, expiry cùng các claims bắt buộc theo contract. Key rotation phải xử lý key ID qua nguồn trusted; không lấy tùy ý URL/key từ token rồi tin. Claims không nên chứa secret chỉ vì token được ký, vì ký không đồng nghĩa mã hóa.

## Hiểu cơ chế từ kết quả quan sát

Revocation và permission freshness là vấn đề lifecycle: token còn hạn có thể chứa quyền đã thay đổi. Access token ngắn hạn, session/state checks hoặc cơ chế revocation có trade-offs. JWT không thay resource authorization; user token hợp lệ vẫn không được đọc tenant khác.

## Khái niệm và mô hình làm việc

JWT signed token bảo vệ integrity, không tự encrypt payload và không tự cấp quyền cho mọi resource.

## Cơ chế và những ranh giới cần giữ

Allowlist algorithm, validate signature, issuer, audience, expiry/not-before với bounded skew; trusted JWKS source và key rotation cache policy.

## Áp dụng vào hệ thống thật

Access token ngắn hạn, principal có scopes nhưng domain còn kiểm tenant/ownership.

## Những đường lỗi cần hiểu

Accept alg từ attacker không policy; decode không verify; trust arbitrary jku URL; stale JWKS cache.

## Lần theo bằng chứng khi có sự cố

Test wrong issuer/audience/algorithm/key, expired tokens và rotation overlap; không log token.

## Đánh đổi và giới hạn sử dụng

Self-contained token giảm introspection latency nhưng revocation khó; opaque tokens có online authority trade-off.

## Thực hành, debugging và kết luận

Test signature sai, algorithm ngoài allowlist, audience/issuer sai và expiry boundaries với clock kiểm soát. Dùng thư viện được duy trì và docs version thật thay vì tự cài crypto. Logs/metrics phải che token; chỉ ghi identifiers/reason có policy.


## Đọc tiếp

- [API security theo trust boundaries](../07-api-design/api-security.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc8725.html)
