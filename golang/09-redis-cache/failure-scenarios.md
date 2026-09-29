# Redis failure game day

## Bài toán và ví dụ đầu tiên

Redis down làm cache hit về zero và DB nhận lượng truy vấn tăng nhiều lần. Cache là tối ưu lúc khỏe nhưng failure có thể chuyển traffic đột ngột sang nguồn chính. Thiết kế fallback cần tính capacity của nơi nhận traffic đó.

## Đi từng bước qua một tình huống

Nếu bình thường 90% reads hit cache, DB chỉ thấy 10%; mất cache có thể tăng read demand gần 10 lần theo giả định giữ nguyên traffic. Circuit breaker tránh mỗi request chờ Redis timeout dài, nhưng fallback vẫn phải có concurrency bound/rate control để DB không sập theo.

## Hiểu cơ chế từ kết quả quan sát

Eviction, timeout, failover và stale data là các failure khác nhau. Retry cache vô hạn làm latency tăng và connection cạn. Cache warmup/recovery có thể tạo stampede; ramp, TTL jitter và coalescing giúp quản lý work thay vì đồng loạt refill toàn keyspace.

## Khái niệm và mô hình làm việc

Cache failure cần policy theo data role: derived cache có fallback; security/rate/idempotency state cần safety decision riêng.

## Cơ chế và những ranh giới cần giữ

Use tight timeout/circuit, bounded fallback to DB, stale cache nếu product cho phép; reconnect backoff+jitter.

## Áp dụng vào hệ thống thật

Simulate Redis unavailable 5 phút, watch DB headroom và error budget.

## Những đường lỗi cần hiểu

Retry storm; all requests fallback DB; fail-open lock/idempotency gây duplicates.

## Lần theo bằng chứng khi có sự cố

Correlate Redis errors, cache misses, DB wait và request latency; verify recovery không refill storm.

## Đánh đổi và giới hạn sử dụng

Availability versus freshness/correctness phải quyết định per endpoint.

## Thực hành, debugging và kết luận

Theo dõi hit ratio, Redis latency/errors, DB QPS/pool wait và user P99 trên cùng timeline. Test outage có giới hạn và kiểm tra degraded response policy. Khôi phục Redis chưa đủ: cần xem DB backlog và cache freshness trở lại mục tiêu.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)

## Thực hành có điều kiện kiểm chứng

Game day đặt cache timeout ngắn hơn request budget, cắt Redis trong60s và đo source DB calls trước/sau. Fallback admission phải giữ DB dưới verified capacity; requests vượt budget trả explicit error/degraded response. Khi Redis hồi phục, ramp refresh và jitter TTL để không tạo đợt stampede thứ hai. Ghi rõ endpoints nào được stale và stale tối đa bao lâu.
