# pgx native và database/sql adapter

## Bài toán và ví dụ đầu tiên

Dịch vụ dùng PostgreSQL muốn type support và protocol features riêng ngoài database/sql. pgx là driver/library cho PostgreSQL; có API native và adapter để đi qua database/sql. Chọn một đường giúp code rõ ai sở hữu pool và semantics nào đang dùng.

## Đi từng bước qua một tình huống

Native pgxpool quản lý pool riêng; database/sql với stdlib adapter dùng pool của sql.DB. Không bọc chồng hai pool một cách vô thức hoặc áp field config của pool này vào pool kia. Rows, transaction và batch results vẫn cần cleanup theo contract API cụ thể.

## Hiểu cơ chế từ kết quả quan sát

Context truyền cancellation nhưng khả năng remote outcome vẫn cần hiểu theo operation. PostgreSQL-specific type mapping, COPY và batching có thể giảm overhead nhưng tạo coupling engine. API/version của driver thay đổi, nên đọc docs cho version trong go.mod trước khi copy snippet.

## Khái niệm và mô hình làm việc

pgx cung cấp PostgreSQL-specific API và pgxpool; stdlib adapter cho code dùng database/sql.

## Cơ chế và những ranh giới cần giữ

Pool/connection lifecycle khác API; native Conn không dùng concurrent tùy ý. Close Rows, BatchResults, release acquired conn; COPY/batch tăng throughput nhưng cần bounded batches.

## Áp dụng vào hệ thống thật

Bulk migration dùng CopyFrom/staging + merge với checkpoint sau commit.

## Những đường lỗi cần hiểu

Quên close BatchResults giữ connection; tạo cả sql.DB và pgxpool vô tình nhân budget.

## Lần theo bằng chứng khi có sự cố

Dùng pgxpool.Stat acquire duration/empty acquire counts và PostgreSQL waits; cancellation test với version driver đã pin.

## Đánh đổi và giới hạn sử dụng

Native features đổi portability; sql.DB phù hợp generic adapters nhưng không cần bọc cả hai layers.

## Thực hành, debugging và kết luận

Integration test với PostgreSQL và pooler dùng thật, gồm cancellation, transaction rollback và nullable/numeric/time fields. Benchmark workload đại diện trước khi đổi driver vì một microbenchmark không phản ánh query plan hay lock. Ghi dependency version trong incident để tái hiện đúng.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/github.com/jackc/pgx/v5)
