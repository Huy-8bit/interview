# Database scaling theo bottleneck

## Bài toán và ví dụ đầu tiên

API scale thêm pods nhưng DB CPU/locks tăng và mọi request chậm hơn. Database scaling cần xác định read, write, connection hoặc storage bottleneck trước khi chọn replicas/shards.

## Đi từng bước qua một tình huống

Bắt đầu query plan, indexes, N+1 và transaction hold time. Read replica có thể giảm read load nhưng có replication lag; read-after-write phải có routing/version policy. Connection pooling giảm churn nhưng nhiều active queries hơn không luôn tăng throughput.

## Hiểu cơ chế từ kết quả quan sát

Write scaling có thể cần partitioning/sharding hoặc đổi data model, kèm cross-shard invariant cost. Vertical scale đơn giản hơn một thời gian nhưng có giới hạn/availability trade-offs. Backups, recovery và replication đều cần đo với volume tăng.

## Khái niệm và mô hình làm việc

Scale database gồm query/index fixes, caching, replicas, partitioning và sharding; mỗi cách giải quyết bottleneck khác.

## Cơ chế và những ranh giới cần giữ

Read replica giảm eligible reads nhưng có lag; vertical scale/IO tuning khác write sharding. Connection pool không tạo DB execution capacity.

## Áp dụng vào hệ thống thật

Read-your-writes route writer; background analytics tách workload khỏi OLTP.

## Những đường lỗi cần hiểu

Replication lag stale status; too many connections; hot row invariant vẫn serialized dù thêm shards.

## Lần theo bằng chứng khi có sự cố

Plans, locks, CPU/IO, WAL, replication lag và working set; xác định read/write/skew.

## Đánh đổi và giới hạn sử dụng

Sharding thêm routing/rebalance/cross-shard complexity; chọn sau evidence.

## Thực hành, debugging và kết luận

Theo dõi QPS, service time, lock/IO và pool wait theo workload. Test failover và stale reads trước đưa replica vào critical path. Chọn thay đổi nhỏ giải quyết bottleneck đã đo; không shard chỉ vì số rows lớn nếu query/index hiện vẫn đáp ứng.


## Đọc tiếp

- [System design framework cho Senior Go](system-design-framework.md)
- [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md)
- [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
