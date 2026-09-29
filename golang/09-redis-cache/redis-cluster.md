# Redis Cluster: slots và hot keys

## Bài toán và ví dụ đầu tiên

Một Redis node không đủ capacity hoặc cần topology phân tán. Redis Cluster chia keyspace thành hash slots để route key tới node; client cần hiểu redirects và topology thay đổi, không chỉ giữ một TCP connection.

## Đi từng bước qua một tình huống

Các key liên quan multi-key operation thường cần cùng slot theo constraint của command; hash tag có thể đặt chúng cùng nhóm nhưng cũng tập trung tải. Một hot key vẫn nóng trên một owner node, nên thêm nodes không tự chia một counter cực hot thành nhiều phần.

## Hiểu cơ chế từ kết quả quan sát

Replication/failover có consistency và durability trade-offs theo cấu hình. Network partitions và stale topology khiến client gặp redirect/retry; retry mutation cần hiểu command semantics. Resharding thêm tải và thay đường đi key trong lúc ứng dụng vẫn chạy.

## Khái niệm và mô hình làm việc

Redis Cluster chia keyspace theo hash slots; một hot key vẫn thuộc một shard.

## Cơ chế và những ranh giới cần giữ

Client xử lý MOVED/ASK theo library; hash tags đặt keys cùng slot khi cần multi-key atomicity nhưng có thể tạo skew. Replication/failover có durability windows tùy config.

## Áp dụng vào hệ thống thật

Partition cache theo tenant/key, monitor per-shard memory/CPU thay aggregate.

## Những đường lỗi cần hiểu

Resharding errors nếu client không cluster-aware; hot tag dồn mọi tenant vào một slot.

## Lần theo bằng chứng khi có sự cố

Inspect slot ownership, redirections, per-node latency và key size distribution.

## Đánh đổi và giới hạn sử dụng

Cluster scale keyspace, không tự scale single key; replicas có consistency/lag trade-off.

## Thực hành, debugging và kết luận

Đo per-node memory/CPU, slot/key skew và redirect errors. Test failover/reshard với client version dùng thật. Chọn cluster khi cần scale tương ứng và có năng lực vận hành; một cache nhỏ có HA phù hợp có thể dễ quản hơn topology lớn không cần thiết.


## Đọc tiếp

- [Database connection pool: 500 requests và 20 connections](../08-database/database-sql-pool.md)
- [distributed-lock](../12-distributed-systems/distributed-lock.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://redis.io/docs/latest/develop/)
