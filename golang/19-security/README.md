# Giữ trust boundary trong backend

Bắt đầu identity và quyền trên resource, rồi theo input tới query, URL/file, token và output. Ví dụ giúp phân biệt authentication với authorization và decode token với verify token. Khi triển khai thực, dùng tài liệu chuẩn/provider đúng version cho protocol; snippets khái niệm không thay review cấu hình của hệ thống cụ thể.

## Bắt đầu và cách thực hành

Bắt đầu với [api-security](api-security.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Security review theo endpoint](api-security.md) | P1 |
| [Vulnerabilities trong Go backend](common-vulnerabilities.md) | P1 |
| [Input validation tại boundaries](input-validation.md) | P1 |
| [JWT validation và key rotation](jwt.md) | P1 |
| [OAuth 2, OIDC và authorization code flow](oauth2.md) | P1 |
| [Secrets: distribution, storage và rotation](secret-management.md) | P1 |
| [TLS: trust, identity và lifecycle](tls.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
