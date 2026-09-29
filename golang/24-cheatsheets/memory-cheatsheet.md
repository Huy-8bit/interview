# Memory Cheatsheet

Review8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

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

## Self-check

Explain one failure, the resource it retains, and the measurement that proves your fix. Trả lời bằng mechanism, không chỉ definition.

[Đọc sâu](../02-memory-runtime/README.md) · [Review ngày cuối](last-day-review.md)
