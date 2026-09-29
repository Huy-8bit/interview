# FastAPI Cheatsheet

- ASGI → middleware → route → dependency → validation → endpoint → serialization.
- `async def`: event loop; `def`: thread pool. Async driver required end-to-end.
- Session per request; transaction at service/use-case boundary; không giữ transaction qua network call.
- Pydantic model là API contract, không expose ORM/entity trực tiếp.
- CPU-heavy work → process/queue. Small best-effort post-response work mới dùng BackgroundTasks.
- AuthN ở token/session; AuthZ tại resource/tenant. Redact secret/PII.
- Đo RPS, p95/p99, error, loop lag, pool wait; timeout/retry/backpressure có budget.
