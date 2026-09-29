# System Design Cheatsheet

## Ví dụ để đọc bảng đúng điều kiện

Bắt đầu API+DB để chỉ ra commit boundary và operation identity. Thêm replica khi capacity/availability yêu cầu, cache khi reads lặp và stale budget cho phép, queue khi hoàn thành sau response là contract hợp lệ. Một estimate mean concurrency=rate×mean time cần hệ ổn định và cùng phạm vi đo; P99 không thay mean trực tiếp. Diagram lớn chỉ có ích khi mỗi thành phần thêm giải quyết một constraint đo được.

Đọc bảng sau như chỉ mục tra cứu. Khi một dòng chưa rõ, mở bài đầy đủ ở link cuối trang để xem walkthrough, failure và phép kiểm chứng; không dùng câu ngắn làm quy tắc tuyệt đối.

Review 8–10 phút; che cột bên phải và tự giải thích bằng một ví dụ.

| Prompt | Điều phải nhớ |
|---|---|
| Start | Requirements, invariant, workload distribution và SLO trước chọn technology. |
| Arithmetic | RPS × mean seconds = mean in-flight; bytes×rate×retention rồi replicas/index overhead. |
| Contract | API status/idempotency, data owner, durable commit point, unknown outcome. |
| Go | Bound workers/queues/pools, ctx budgets, shared clients và graceful drain. |
| Failure | Response lost after commit, cache down, lag, stale owner, schema skew, overload. |
| Evidence | User SLIs + queue age + profiles/traces + durable reconciliation. |
| Scale | Find bottleneck, capacity knee, max replicas/surge budgets; shard khi justified. |
| Evolution | State assumptions, next measured trigger, safe migration và rollback data plan. |


[Đọc sâu](../13-system-design/README.md) · [Review ngày cuối](last-day-review.md)
