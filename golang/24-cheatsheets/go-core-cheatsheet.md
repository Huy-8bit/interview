# Go Core Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Một slice b=a[:2] chia sẻ array với a, nên b[0]=100 đổi dữ liệu a. Append vào b chỉ tách storage khi cần capacity mới; gán slice header không clone phần tử. Bảng dưới dùng các từ alias/copy để nhắc tình huống này, không có nghĩa mọi copy struct đều độc lập sâu. Với interface, giữ cặp dynamic type/value trong đầu để thấy vì sao nil pointer trong error vẫn làm err khác nil.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

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


[Đọc sâu](../01-go-core/README.md) · [Review ngày cuối](last-day-review.md)
