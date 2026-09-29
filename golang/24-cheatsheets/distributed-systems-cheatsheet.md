# Distributed Systems Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Timeout | Unknown outcome; not proof of failure. Retry stable logical ID khi replay-safe. |
| Delivery | At-least-once có duplicates; exactly-once claim phải nêu transaction boundary. |
| Idempotency | Unique key + request hash + effect/result durable; retention≥replay horizon. |
| Outbox | Domain+intent same Tx; relay có duplicate window; idempotent consumers. |
| Ordering | Partition order khác completion order; commit contiguous completed prefix. |
| Lease | Expiry không kill old owner; target fencing/version check bảo vệ writes. |
| Saga | Local transactions+compensations, không rollback thời gian; reconciliation cần owner. |
| Backpressure | λ>μ thì queue tăng; recovery≈backlog/(μ−λ); bounded retries/admission. |

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../12-distributed-systems/README.md) · [Review ngày cuối](last-day-review.md)
