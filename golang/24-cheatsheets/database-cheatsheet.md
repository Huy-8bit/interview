# Database Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Ba connections đều đang bận làm query thứ tư chờ acquire; nó có thể hết deadline trước khi SQL tới server. Rows hoặc Tx giữ slot tới khi lifecycle kết thúc. Tăng pool có thể chuyển queue xuống DB và làm locks/CPU tệ hơn; trước hết xem hold time và tổng budget replicas. Transaction cùng DB bảo vệ invariant local, không atomic với một HTTP provider ngoài.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

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


[Đọc sâu](../08-database/README.md) · [Review ngày cuối](last-day-review.md)
