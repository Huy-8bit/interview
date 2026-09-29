# Concurrency Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Caller timeout khi worker còn tính rồi worker send vào channel không còn receiver sẽ leak. Cancel phát tín hiệu; send phải select với tín hiệu đó hoặc có protocol receiver khác, và owner còn cần join nếu phải biết cleanup xong. WaitGroup không gửi cancel, channel buffer không tự là durable queue và atomic pointer không làm nested map bất biến. Các dòng bảng chỉ đúng khi ownership và invariant đã được xác định.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Ownership | Mỗi go: ai tạo, ai cancel, block ở đâu, ai join? |
| Channel | Nil send/receive block; closed send panic; closed receive drain rồi zero,false. |
| Select | Multiple ready chọn pseudo-random; không ưu tiên cancel; default trong loop có thể spin. |
| Mutex | Protect whole invariant; no copy after use, no reentrant; tránh I/O dưới lock. |
| RWMutex | Không upgrade/recursive lock; benchmark với Mutex, readers nhiều chưa đủ lý do. |
| Atomic | Counter/small transitions; nhiều atomic fields không tạo transaction. |
| WaitGroup | Add trước go, Done guaranteed, Wait là join; không truyền error. |
| Pool | Bound workers, queue count/bytes và downstream; overload có reject/drop/durable policy. |


[Đọc sâu](../04-concurrency/README.md) · [Review ngày cuối](last-day-review.md)
