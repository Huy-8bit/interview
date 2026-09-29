# Caching patterns và consistency

## Bài toán và ví dụ đầu tiên

Một cache có thể được điền khi đọc, khi ghi hoặc theo batch refresh. Chọn pattern từ bên nào biết dữ liệu đổi, freshness cần bao lâu và cái giá khi cache lỗi, không chỉ từ thuật ngữ phổ biến.

## Đi từng bước qua một tình huống

Cache-aside để application đọc DB khi miss; write-through cập nhật cache trong write flow theo contract; write-behind trì hoãn ghi nguồn phía sau và phải giải quyết durability/reordering. Refresh-ahead làm mới trước expiry nhưng có thể tạo work cho key không còn ai dùng.

## Hiểu cơ chế từ kết quả quan sát

Mỗi pattern có failure boundary: DB commit mà cache update fail, cache nhận write nhưng durable store chưa có, hoặc refresh cũ overwrite version mới. Cache key và versioning phải giữ tenant/schema, còn invalidation cần owner rõ. Không có pattern loại bỏ mọi trade-off latency, consistency và availability.

## Khái niệm và mô hình làm việc

Cache-aside, write-through và write-behind khác ownership của update và failure window.

## Cơ chế và những ranh giới cần giữ

Cache-aside app đọc cache rồi DB; write-through đồng bộ cả path theo protocol; write-behind async cần durable queue và ordering. TTL chỉ giới hạn staleness theo giả định update/refresh.

## Áp dụng vào hệ thống thật

Product catalog chịu stale vài chục giây; payment authorization dùng authoritative state.

## Những đường lỗi cần hiểu

DB commit thành công nhưng invalidate fail; stale refill đè dữ liệu mới; negative cache giữ not-found quá lâu.

## Lần theo bằng chứng khi có sự cố

Track version/age, compare sampled cache với source và inspect invalidation events.

## Đánh đổi và giới hạn sử dụng

Cache giảm read load nhưng thêm consistency system; không cache nếu working set/hit rate không có lợi.

## Thực hành, debugging và kết luận

Dựng timeline failure rồi kiểm tra điều người dùng thấy. Đo hit ratio theo route/key class cùng total DB load; tỷ lệ hit cao có thể che một hot miss rất đắt. Bắt đầu pattern đơn giản đáp ứng stale budget rồi thêm coordination khi đo được vấn đề.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)
