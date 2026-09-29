# Redis atomic rate limiting

## Bài toán và ví dụ đầu tiên

Nhiều API replicas cần chia sẻ quota tenant. Nếu mỗi process đếm riêng 100 request/s thì 10 replicas có thể cho gần 1000/s. Redis có thể giữ state chung và thực hiện cập nhật counter/tokens atomically theo thuật toán.

## Đi từng bước qua một tình huống

Token bucket lưu lượng token và thời điểm refill; mỗi request tính token mới rồi tiêu trong một operation atomic hoặc script. GET rồi SET từ client có race. Key TTL cần cleanup state tenant không hoạt động nhưng không được reset quota vô ý ở một boundary sai.

## Hiểu cơ chế từ kết quả quan sát

Distributed limiter phụ thuộc clock/policy và Redis availability. Fail-open giúp availability nhưng có thể mất bảo vệ overload; fail-closed giữ quota nhưng có thể làm toàn API lỗi khi Redis down. Có thể dùng local fallback bound theo contract, nhưng phải giải thích mức sai số và capacity.

## Khái niệm và mô hình làm việc

Distributed limiter cần check và update atomic để nhiều instances dùng chung quota.

## Cơ chế và những ranh giới cần giữ

Lua script/token bucket hoặc sliding window theo requirements; bound key TTL/cardinality và clock assumptions. Multi-key operations trong cluster cần cùng slot khi API yêu cầu.

## Áp dụng vào hệ thống thật

Tenant bucket với capacity 100, refill 20/s; chỉ sample debug cho từng tenant tránh metrics cardinality vô hạn.

## Những đường lỗi cần hiểu

INCR rồi EXPIRE tách commands có crash window; clock skew; limiter outage gây policy không rõ.

## Lần theo bằng chứng khi có sự cố

Test concurrent acquire, TTL existence và deny ratio; theo dõi script latency.

## Đánh đổi và giới hạn sử dụng

Central accuracy đổi availability/latency; local fallback phải có conservative budget.

## Thực hành, debugging và kết luận

Test concurrent replicas, burst, thời gian boundary và Redis unavailable. Metrics reject lý do quota khác lỗi limiter. Quota theo tenant cần authentication trước, còn giới hạn thô theo IP có thể đặt sớm để bảo vệ login với awareness về proxy/NAT.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)
