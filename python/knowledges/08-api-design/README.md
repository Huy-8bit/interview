# API Design

Module này được học theo **Why → How → Internals → Flow → Failure → Trade-off → Production**. Không đọc alphabet; đi theo dependency dưới đây và tự vẽ lại diagram trước khi xem.

## Learning order

[Rest API](rest-api.md) → [Idempotency](idempotency.md) → [Retry Timeout](retry-timeout.md) → [Authentication Authorization](authentication-authorization.md) → [API Security](api-security.md)

## Must know

- [Rest API](rest-api.md)
- [Idempotency](idempotency.md)
- [Retry Timeout](retry-timeout.md)
- [Authentication Authorization](authentication-authorization.md)
- [API Security](api-security.md)

## Nice to know / second pass

- [API Versioning](api-versioning.md)
- [Pagination](pagination.md)
- [Rate Limiting](rate-limiting.md)
- [Websocket](websocket.md)

## Recommended exercises

1. Giải thích mỗi Must-know topic trong 2 phút, không nhìn note; interviewer hỏi “why?” ít nhất ba lần.
2. Vẽ request/data/failure flow từ trí nhớ và đánh dấu source of truth, queue, timeout, retry, metric.
3. Chọn một production incident liên quan **API Design**, trình bày mitigation trước root cause và long-term prevention.
4. Load/fault test một assumption: bottleneck, duplicate, stale state hoặc dependency outage.

## All topics

- [Rest API](rest-api.md)
- [API Versioning](api-versioning.md)
- [Pagination](pagination.md)
- [Idempotency](idempotency.md)
- [Rate Limiting](rate-limiting.md)
- [Authentication Authorization](authentication-authorization.md)
- [Websocket](websocket.md)
- [Retry Timeout](retry-timeout.md)
- [API Security](api-security.md)

[← Main Dashboard](../README.md)
