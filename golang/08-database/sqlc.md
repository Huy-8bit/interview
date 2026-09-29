# sqlc: SQL làm contract

## Bài toán và ví dụ đầu tiên

Team muốn giữ SQL viết tay nhưng không muốn tự viết Scan cho mọi query. sqlc đọc schema và query để sinh Go methods/types, giúp một số sai lệch kiểu hoặc tham số xuất hiện ở bước generate/build.

## Đi từng bước qua một tình huống

Developer viết query có tên và cardinality phù hợp, chạy generator rồi gọi method sinh ra qua DB/Tx adapter. File generated nên được tái tạo theo quy trình, không sửa thủ công rồi kỳ vọng lần generate sau giữ lại. Migration/schema đầu vào phải tương ứng query code đang dùng.

## Hiểu cơ chế từ kết quả quan sát

Code generation kiểm tra một lớp contract nhưng không chứng minh query nhanh hoặc migration an toàn khi deploy. Null semantics, isolation, index và dữ liệu skew vẫn là runtime concerns. Generated method compile được chưa chứng minh query chạy trên DB version thật với permissions/config thật.

## Khái niệm và mô hình làm việc

sqlc generate typed Go methods từ schema/query definitions, không thay runtime DB validation.

## Cơ chế và những ranh giới cần giữ

Pin generator version, review SQL và generated diff; tx-bound queries dùng WithTx hoặc DBTX pattern theo generated API. Schema input phải khớp migrations.

## Áp dụng vào hệ thống thật

Checkout queries giữ type-safe scan và SQL dễ review.

## Những đường lỗi cần hiểu

Generated code compile nhưng production schema khác; optional filters tạo query plan kém.

## Lần theo bằng chứng khi có sự cố

Regenerate trong CI và fail dirty diff; integration test query trên migrated database.

## Đánh đổi và giới hạn sử dụng

Generated API tốt cho stable SQL; highly dynamic query builder có thể cần cách khác.

## Thực hành, debugging và kết luận

CI kiểm tra generated output không drift và integration test schema/query. Khi incident latency tăng, đọc SQL thực chứ không dừng ở tên method generated. sqlc phù hợp team muốn SQL minh bạch; một ORM có thể tiện hơn cho CRUD động nhưng cần kiểm soát query tương đương.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://docs.sqlc.dev/en/stable/)
