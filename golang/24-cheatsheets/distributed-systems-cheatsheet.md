# Distributed Systems Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Service commit payment nhưng response mất, caller nhận timeout. Retry với identity mới có thể double charge; giữ stable key, query provider state và lưu pending/unknown giúp phục hồi. Outbox đưa domain state và event intent vào cùng DB transaction nhưng relay vẫn có thể publish duplicate sau crash. Lease hết không tự dừng worker cũ, nên stale effect cần fencing/version hoặc idempotency ở sink.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

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


[Đọc sâu](../12-distributed-systems/README.md) · [Review ngày cuối](last-day-review.md)
