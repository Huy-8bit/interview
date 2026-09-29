# HTTP Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Server | Explicit timeouts, body/header bounds, request context và admission. |
| Client | Reuse for policy; nil Transport dùng shared DefaultTransport. |
| Transport | Sở hữu pool; new per request tạo TCP/TLS churn. |
| Body | Do success phải Close kể cả status lỗi; HTTP/1 EOF+Close thường cần cho reuse; bound drain. |
| Timeout | Client.Timeout gồm body; header timeout không bound body; ctx không undo remote commit. |
| Pools | Idle cap khác active cap; H2 streams không bằng socket count; budget toàn fleet. |
| Middleware | Ordering rõ, preserve streaming/hijack interfaces, không write sau handler return. |
| Shutdown | Fresh deadline context, stop intake, drain/join, close DB cuối; WebSockets quản lý riêng. |

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../06-http-backend/README.md) · [Review ngày cuối](last-day-review.md)
