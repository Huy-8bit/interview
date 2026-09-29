# HTTP Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Client.Do trả response chưa có nghĩa body đã đọc xong. Caller cần size policy, đọc/Close đúng để trả tài nguyên và giúp HTTP/1 reuse khi đủ điều kiện. Pool ở Transport, nên khởi tạo một custom Transport cho mỗi request có thể mất reuse. Timeout dial chỉ bảo vệ kết nối ban đầu, không giới hạn toàn thời gian đọc body; context/client policy cần phù hợp request hữu hạn hoặc stream.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

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


[Đọc sâu](../06-http-backend/README.md) · [Review ngày cuối](last-day-review.md)
