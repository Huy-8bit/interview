# Memory Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Nếu allocation/request tăng nhưng live heap sau GC gần cũ, ưu tiên xem churn qua alloc_space và GC CPU. Nếu live heap tăng sau mỗi burst rồi không giảm khi drain, ưu tiên retention: cache, slice view hoặc goroutine giữ references. RSS còn có phần ngoài heap, nên một dòng “heap thấp” không đủ bác bỏ container memory pressure. Stack/heap placement là quyết định compiler theo lifetime, không suy chỉ từ dấu &.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Placement | Compiler escape + inlining quyết định; return pointer không luôn heap. |
| Diagnostic | go build -gcflags="-m=2"; moved to heap khác application leak. |
| GC | Reachability tracing, concurrent mark, barrier, STW coordination, sweep/scavenge khác nhau. |
| Version | Go 1.26 Green Tea default; mental model không là exact private struct contract. |
| GOGC | Trade CPU/frequency lấy heap headroom; measure workload. |
| GOMEMLIMIT | Soft runtime-managed memory limit; chừa native/OS headroom, không hard RSS cap. |
| Profiles | inuse_space retained; alloc_space churn; RSS còn memory ngoài Go heap. |
| Leaks | Reachable cache/sub-slice/closure/G; GC không Close resources hoặc kill worker. |


[Đọc sâu](../02-memory-runtime/README.md) · [Review ngày cuối](last-day-review.md)
