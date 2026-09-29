# Redis lock và fencing

## Bài toán và ví dụ đầu tiên

Hai replicas cùng refresh một expensive key và muốn chỉ một bên làm. Redis lease lock có thể giảm công việc trùng, nhưng lease hết trong lúc holder pause làm hai holder cùng tồn tại từ góc nhìn application.

## Đi từng bước qua một tình huống

Acquire bằng operation atomic có owner token và TTL theo thiết kế. Release phải so owner token trước khi delete để holder cũ không xóa lease mới. Nếu công việc dài, renewal cũng có thể fail; worker phải coi mất lease là mất authority, không chỉ log rồi tiếp tục ghi.

## Hiểu cơ chế từ kết quả quan sát

Với cache refill cho phép duplicate, lock có thể là tối ưu best-effort. Với payment hoặc write nguy hiểm, cần storage kiểm tra fencing/version hoặc invariant durable; lock TTL đơn lẻ không đủ. Network failure làm kết quả acquire/release có thể chưa rõ, phải xử lý theo safety cần thiết.

## Khái niệm và mô hình làm việc

Lease bằng TTL giảm concurrent work nhưng expired owner vẫn có thể chạy; mutual exclusion ở lock server chưa đủ bảo vệ external writes.

## Cơ chế và những ranh giới cần giữ

SET key token NX PX acquire; release atomically compare token rồi delete bằng script. Với correctness-critical writes, resource cần reject stale fencing token monotonic từ authority phù hợp.

## Áp dụng vào hệ thống thật

Cache rebuild coalescing có thể chấp nhận duplicate; money invariant dùng DB constraint/transaction thay lock Redis đơn thuần.

## Những đường lỗi cần hiểu

Process pause quá TTL, owner mới chạy, owner cũ wake ghi đè; plain DEL xóa lock người khác.

## Lần theo bằng chứng khi có sự cố

Record token/lease timestamps và target versions; inject pause/network partition.

## Đánh đổi và giới hạn sử dụng

Redis lease phù hợp best-effort exclusion; không tuyên bố universal safety cho distributed lock không nêu timing assumptions.

## Thực hành, debugging và kết luận

Test holder pause vượt TTL, token mismatch và Redis failover. Đo lock wait và duplicate refill, tránh giữ lock trong network call vô hạn. Nếu invariant nằm trong PostgreSQL, unique/conditional update thường dễ chứng minh hơn thêm distributed lock bên ngoài.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)
