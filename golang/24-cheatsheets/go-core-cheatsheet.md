# Go Core Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Slice | Header copy, shared backing array; append có thể reallocate; clone để detach retention. |
| Map | Comparable keys; iteration unordered; concurrent read/write cần synchronization; Go 1.24+ default Swiss Tables. |
| Interface | Dynamic type + value; typed nil pointer trong interface thường !=nil. |
| Methods | T và *T có method sets khác; method call convenience không thay interface satisfaction. |
| Errors | %w giữ cause; Is tìm condition, As tìm type, Join tạo error tree; log tại boundary. |
| Defer | Arguments evaluate lúc đăng ký, chạy LIFO; named return có thể bị sửa; defer trong loop giữ resources. |
| Panic | Unwind cùng goroutine; recover trong deferred function; expected failures dùng error. |
| Generics | Type set cho thuật toán; interface cho behavior/runtime substitution; không abstract mọi thứ. |

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../01-go-core/README.md) · [Review ngày cuối](last-day-review.md)
