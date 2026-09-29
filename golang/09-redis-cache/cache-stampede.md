# Cache stampede và refresh coalescing

## Bài toán và ví dụ đầu tiên

Một key hot hết TTL đúng lúc 500 request đến. Tất cả miss và cùng query DB cho cùng dữ liệu, khiến DB overload. Stampede là nhiều actor đồng thời làm công việc refill giống nhau khi cache mất hoặc hết hạn.

## Đi từng bước qua một tình huống

Trong một process, singleflight có thể gom các request cùng key vào một lần load rồi chia kết quả. Nhiều replicas vẫn có thể mỗi replica load một lần; distributed coordination hoặc stale-while-revalidate có failure model khác. TTL jitter làm nhiều key không hết hạn cùng lúc, nhưng không tự giải quyết một key cực hot.

## Hiểu cơ chế từ kết quả quan sát

Stale-while-revalidate trả value cũ trong khoảng được product cho phép rồi refresh có owner. Cần max stale age và policy khi refresh fail; không dùng cho dữ liệu mà đọc cũ gây lỗi quyền hoặc số dư. Loader phải có deadline và concurrency bound để stampede không chỉ chuyển từ DB sang goroutine chờ.

## Khái niệm và mô hình làm việc

Nhiều callers cùng miss một hot key làm N identical source queries.

## Cơ chế và những ranh giới cần giữ

Singleflight coalesce trong process; cross-pod still multiple loads. TTL jitter tránh simultaneous expiry; early refresh/stale response cần explicit freshness bound.

## Áp dụng vào hệ thống thật

Hot catalog page dùng shared refresh owner có timeout riêng, callers có wait budget.

## Những đường lỗi cần hiểu

Leader caller canceled kéo shared refresh nếu dùng sai ctx; unbounded refresh map; backend outage phá mọi refresh.

## Lần theo bằng chứng khi có sự cố

Measure source loads per cache key sample, fan-in waiter count và refresh duration.

## Đánh đổi và giới hạn sử dụng

Coalescing giữ waiters nên vẫn bound concurrency; không biến tất cả requests thành chờ một refresh vô hạn.

## Thực hành, debugging và kết luận

Test xóa hot key dưới tải và so DB QPS, P99, số load thực. Cache recovery nên ramp để tránh burst refill. Negative caching và request coalescing có ích nhưng phải key đúng tenant/input để không chia nhầm kết quả giữa người dùng.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)
