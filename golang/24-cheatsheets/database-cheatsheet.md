# Database Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| sql.DB | Shared pool handle; Open chưa chắc kết nối, PingContext kiểm startup. |
| Rows | Close mọi paths và check Err sau Next loop; QueryRow errors tại Scan. |
| Tx | Use tx cho mọi operation; Commit errors quan trọng; rollback cleanup không che main error. |
| Pool | MaxOpen active+idle cap; MaxIdle reuse; lifetime/idle time khác nhau. |
| Stats | InUse/Idle/Open gauges; WaitCount/WaitDuration cumulative, đọc deltas. |
| 500/20 | Excess requests chờ hoặc cancel; throughput planning từ hold time và DB capacity. |
| SQL | Parameterized values, allowlisted identifiers, tenant predicates và constraints. |
| Consistency | Isolation theo invariant; serializable retry whole Tx; replica lag ảnh hưởng reads. |

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../08-database/README.md) · [Review ngày cuối](last-day-review.md)
