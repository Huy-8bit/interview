# N+1 queries

## Bài toán và ví dụ đầu tiên

Endpoint lấy 100 orders bằng một query rồi lặp lấy customer cho từng order. Tổng là 101 query. Mỗi query có thể chỉ 2 ms nhưng latency và connection pressure cộng dồn đáng kể; đây là N+1.

## Đi từng bước qua một tình huống

Dùng join nếu dữ liệu phù hợp hoặc thu customer IDs rồi batch query có giới hạn, sau đó map kết quả về orders. Batch không được bỏ xử lý missing/null customer và ordering. Nếu list có 10000 items thì một IN cực lớn cũng cần chia batch hoặc đổi API pagination.

## Hiểu cơ chế từ kết quả quan sát

N+1 là vấn đề số round trips và execution pattern, không chỉ ORM. Raw SQL trong for vẫn tạo N+1. Eager loading giảm query nhưng có thể nhân số row khi join quan hệ nhiều-nhiều, khiến truyền và decode dư dữ liệu; chọn shape theo response cần.

## Khái niệm và mô hình làm việc

Một query lấy danh sách rồi N queries lấy dữ liệu con làm round trips tăng theo page size.

## Cơ chế và những ranh giới cần giữ

Batch IDs, join hoặc preload có giới hạn; join nhiều one-to-many có thể nhân rows nên aggregation và pagination cần cẩn thận.

## Áp dụng vào hệ thống thật

List 100 orders trả items qua hai bounded queries thay 101 queries.

## Những đường lỗi cần hiểu

Join fix làm response 100x lớn; pagination trên joined rows cắt thiếu entities.

## Lần theo bằng chứng khi có sự cố

Trace query count theo page size, tổng DB time và bytes/rows scanned.

## Đánh đổi và giới hạn sử dụng

Batch giảm RTT nhưng payload/memory tăng; không load mọi relation mặc định.

## Thực hành, debugging và kết luận

Trong trace đếm query/request và so với page size. Test page 1, 10, 100 để thấy query count có tăng tuyến tính không. Thêm concurrency cho 100 query có thể giảm latency đơn request nhưng khuếch đại tải DB; giảm số query trước khi song song hóa.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/database/)
