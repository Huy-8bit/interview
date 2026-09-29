# Cache-aside: miss path cũng là production path

## Bài toán và ví dụ đầu tiên

API kiểm tra cache, miss thì đọc DB và ghi cache. Cách này dễ thêm vào hệ thống sẵn có nhưng update path phải giải quyết cache cũ. Cache-aside là application tự quản việc lấy/điền cache quanh nguồn dữ liệu chính.

## Đi từng bước qua một tình huống

A đọc DB value v1 sau miss; B cập nhật DB lên v2 rồi invalidate cache; A sau đó ghi v1 vào cache. Cache vẫn stale dù B đã delete đúng một lần. Timeline này cho thấy delete-after-write không tạo consistency mạnh khi read-fill đua với update.

## Hiểu cơ chế từ kết quả quan sát

TTL giới hạn retention theo policy nhưng không bảo đảm read-your-writes tức thì. Versioned values, invalidation events hoặc routing read nguồn chính sau write có thể đáp ứng yêu cầu cụ thể, mỗi cách thêm chi phí. Negative caching cho not-found cần TTL riêng để không che resource vừa tạo quá lâu.

## Khái niệm và mô hình làm việc

App sở hữu load và cache fill; miss đi DB và phải có concurrency budget.

## Cơ chế và những ranh giới cần giữ

Read key, on miss coalesce same-key loads, query source, set TTL+jitter; invalidation sau successful write vẫn cần versioning nếu stale refill không chấp nhận.

## Áp dụng vào hệ thống thật

Cache product details; use short negative TTL cho missing ID để giảm repeated misses.

## Những đường lỗi cần hiểu

Cold start mọi pods miss cùng lúc; Redis down tất cả fallback DB.

## Lần theo bằng chứng khi có sự cố

Measure hit ratio theo route, load coalescing wait và DB QPS khi cache bypass.

## Đánh đổi và giới hạn sử dụng

Stale-while-revalidate giảm latency nhưng cần stale bound và owner refresh.

## Thực hành, debugging và kết luận

Test đua fill/update và expiry đồng loạt, không chỉ hit/miss đơn lẻ. Đo stale age nếu semantics quan trọng. Giữ DB là source of truth và có giới hạn fallback traffic khi cache down; cache-aside không tự làm database đủ capacity chịu mọi miss.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)
