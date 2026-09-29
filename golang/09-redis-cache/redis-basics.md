# Redis: data structures và bounded memory

## Bài toán và ví dụ đầu tiên

Một API đọc cùng profile nhiều lần và muốn tránh query DB lặp. Redis lưu dữ liệu trong bộ nhớ với nhiều data structures và protocol network; cache hit có thể giảm latency nhưng thêm dependency và freshness policy.

## Đi từng bước qua một tình huống

Key profile:tenant:user có value được serialize và TTL. Cache miss đọc DB rồi điền cache. TTL là thời gian key có thể tồn tại theo expiration policy, không tự đồng bộ với mọi update DB. Tenant và version schema cần nằm trong key/encoding khi ảnh hưởng ý nghĩa dữ liệu.

## Hiểu cơ chế từ kết quả quan sát

Redis command atomic theo phạm vi của command/script được hệ thống hỗ trợ, nhưng chuỗi GET rồi SET ở client không tự atomic. Persistence/replication cấu hình quyết định durability khác nhau; cache có thể mất và phải rebuild, còn dùng Redis làm nguồn sự thật cần contract chặt hơn.

## Khái niệm và mô hình làm việc

Redis là in-memory data server với persistence/replication tùy config; không mặc nhiên là durable source of truth.

## Cơ chế và những ranh giới cần giữ

Strings/hashes/sets/sorted sets/streams phục vụ operations khác nhau. Command atomicity khác atomicity của read-modify-write nhiều commands. TTL, eviction policy và maxmemory cần chọn theo data role.

## Áp dụng vào hệ thống thật

Cache derived user profile với TTL jitter, bounded value size và metrics hit/miss/evicted.

## Những đường lỗi cần hiểu

Big keys/slow commands chặn event processing; eviction xóa key app tưởng durable.

## Lần theo bằng chứng khi có sự cố

Latency, memory, evictions, key cardinality và slowlog; tránh KEYS toàn keyspace trong production.

## Đánh đổi và giới hạn sử dụng

In-memory latency tốt nhưng RAM/persistence trade-off; SQL constraints vẫn cho durable invariant.

## Thực hành, debugging và kết luận

Đo hit ratio, latency, memory, eviction và key distribution. Test Redis down xem DB chịu được miss traffic không. Pool client/concurrency và context vẫn cần: gọi cache nhanh không có nghĩa được phép chờ vô hạn. Chỉ cache khi read pattern và stale tolerance biện minh chi phí.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)
