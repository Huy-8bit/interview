# ORM, raw SQL và query ownership

## Bài toán và ví dụ đầu tiên

Một nhóm cần CRUD nhanh, nhóm khác có query phân tích phức tạp. ORM và raw SQL là lựa chọn về mức abstraction và workflow, không là thước đo người viết code giỏi hơn. Cả hai phải giữ query, transaction và resource ownership quan sát được.

## Đi từng bước qua một tình huống

ORM có thể sinh preload/join tiện nhưng cũng tạo N+1 nếu mỗi record lazy-load relation. Raw SQL cho thấy rõ câu lệnh nhưng tăng việc Scan/mapping. Generated SQL methods là một điểm giữa: viết SQL có chủ đích, dùng type Go được sinh để giảm boilerplate.

## Hiểu cơ chế từ kết quả quan sát

Boundary repository nên lộ semantics như transaction, not-found và pagination mà service cần. Đừng che mọi query thành một generic CRUD API nếu domain cần conditional update để giữ invariant. Ngược lại, đừng đưa chi tiết driver vào mọi layer khiến đổi schema lan rộng không kiểm soát.

## Khái niệm và mô hình làm việc

Chọn abstraction theo query visibility, type safety và team workflow; Go không buộc một ORM.

## Cơ chế và những ranh giới cần giữ

ORM giảm CRUD boilerplate; raw SQL kiểm soát plans; generated SQL như sqlc giữ query explicit và typed methods. Tất cả cần constraints/transactions.

## Áp dụng vào hệ thống thật

Query reporting phức tạp dùng SQL reviewable; CRUD đơn giản có thể dùng ORM nếu đo N+1 và transaction boundaries.

## Những đường lỗi cần hiểu

Lazy loading N+1; query hidden trong loop; abstraction không expose timeout/Tx.

## Lần theo bằng chứng khi có sự cố

Đếm queries/request, đọc emitted SQL và EXPLAIN trên dữ liệu đại diện.

## Đánh đổi và giới hạn sử dụng

Không bọc ORM bằng generic repository tới mức mất khả năng tối ưu query.

## Thực hành, debugging và kết luận

So bằng query count, explain plan, testability, migration workflow và kỹ năng team. Log SQL đã sanitize ở môi trường phù hợp để review actual queries. Chọn công cụ giúp duy trì contract đúng; performance bottleneck thường ở query/data access pattern hơn ở tên thư viện.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/database/)
