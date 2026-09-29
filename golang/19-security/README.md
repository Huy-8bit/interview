# Security

Bảo vệ identity/resource/input và secrets boundaries.

## Reading map

| Bài | Ưu tiên |
|---|---|
| [Security review theo endpoint](api-security.md) | P1 |
| [Vulnerabilities trong Go backend](common-vulnerabilities.md) | P1 |
| [Input validation tại boundaries](input-validation.md) | P1 |
| [JWT validation và key rotation](jwt.md) | P1 |
| [OAuth2, OIDC và authorization code flow](oauth2.md) | P1 |
| [Secrets: distribution, storage và rotation](secret-management.md) | P1 |
| [TLS: trust, identity và lifecycle](tls.md) | P1 |

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
