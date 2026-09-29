# Sharding và partition ownership

## Bài toán và ví dụ đầu tiên

Một dataset hoặc write workload vượt khả năng một owner DB. Sharding chia dữ liệu thành các phần có owner khác nhau; key lựa chọn quyết định locality, balance và operation nào phải đi qua nhiều shards.

## Đi từng bước qua một tình huống

Shard theo tenant giữ query tenant-local nhưng tenant rất lớn có thể hot. Hash userID cân bằng hơn nhưng report cross-user phải fanout. Directory/routing map cần version và migration protocol để chuyển shard mà client không ghi hai nơi hoặc mất key.

## Hiểu cơ chế từ kết quả quan sát

Cross-shard transaction và uniqueness khó hơn local DB constraints. Resharding cần copy, catch-up changes, verification và cutover authority. More shards thêm operational overhead, backups và failure cases; một hot entity không được chia chỉ nhờ tăng shard count.

## Khái niệm và mô hình làm việc

Sharding chia dữ liệu/throughput theo key qua authorities; chọn key quyết định locality và hot spots.

## Cơ chế và những ranh giới cần giữ

Hash phân đều average; range hỗ trợ scans nhưng có skew; directory routing linh hoạt nhưng thêm metadata authority. Rebalance cần copy+CDC+cutover epoch.

## Áp dụng vào hệ thống thật

Tenant-sharded data giữ tenant transactions local, có special handling cho hot tenant.

## Những đường lỗi cần hiểu

Cross-shard joins/transactions; key migration double writes; one large tenant saturates shard.

## Lần theo bằng chứng khi có sự cố

Per-shard load/storage/lag, routing version và invariant reconciliation sau move.

## Đánh đổi và giới hạn sử dụng

Không shard chỉ vì table lớn; index/query/access pattern có thể đủ.

## Thực hành, debugging và kết luận

Dùng workload distribution thật để ước lượng skew. Test stale routing, shard move và partial outage. Giữ một shard tới khi có bằng chứng cần tách, rồi chọn key từ invariant/access patterns thay vì một hash đơn giản không xét product.


## Đọc tiếp

- [System design framework cho Senior Go](system-design-framework.md)
- [Design High-Throughput API — 20,000 RPS](design-high-throughput-api.md)
- [Design Migration Platform — 4–5 Billion Records](design-migration-platform.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
