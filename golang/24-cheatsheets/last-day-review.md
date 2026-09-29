# Last-day review — 110 minutes

Trang này dành cho người đã hoàn thành các bài nền tảng. Với mỗi nhóm, chọn một ví dụ và diễn giải từ input tới output trước khi xem gợi ý. Nếu chỉ nhớ tên primitive mà không xác định được ai sở hữu state hoặc điểm dừng, quay lại giáo trình thay vì cố hoàn thành lịch ôn trong một buổi. Các mốc thời gian là cách chia buổi, không là chuẩn đánh giá hiểu biết.

Không học thêm runtime trivia. Tập giải thích invariant, failure và evidence từ các bài đã làm.

| Phút | Bài | Output |
|---|---|---|
| 0–10 | [Go core](go-core-cheatsheet.md) | Typed nil, aliasing, errors và defer trap |
| 10–20 | [Scheduler](scheduler-cheatsheet.md) | Vẽ G-M-P, syscall versus netpoll |
| 20–30 | [Memory](memory-cheatsheet.md) | Escape, live heap/churn, GOGC/limit |
| 30–40 | [Concurrency](concurrency-cheatsheet.md) | Close/cancel/join cho worker pool |
| 40–50 | [HTTP](http-cheatsheet.md) | Client/Transport/body/pool/timeouts |
| 50–60 | [Database](database-cheatsheet.md) | 500 requests/20 conns, Rows/Tx cleanup |
| 60–70 | [Distributed](distributed-systems-cheatsheet.md) | Crash sau commit trước ack |
| 70–80 | [System design](system-design-cheatsheet.md) | Estimate20k RPS và Redis failure |
| 80–95 | [Production runbooks](../20-production-scenarios/README.md) | Chọn profile cho CPU, memory,20k G |
| 95–105 | [STAR](../22-behavioral/star-method.md) | Hai stories thật, rõ contribution |
| 105–110 | [Checklist](../00-roadmap/interview-checklist.md) | Chốt 3 gaps và notes ngắn |

Nếu bí một câu, quay lại đúng deep dive được link; không học thuộc answer bank mà bỏ mechanism.
