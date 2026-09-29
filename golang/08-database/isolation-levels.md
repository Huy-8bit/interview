# Isolation levels trong PostgreSQL

## Bài toán và ví dụ đầu tiên

Hai bác sĩ cùng thấy người kia đang trực nên mỗi người tự chuyển off-call. Hai transaction có thể đều hợp lệ theo snapshot riêng nhưng kết quả cuối không còn ai trực. Isolation quyết định các transaction nhìn concurrent changes ra sao; nó không chỉ là bật/tắt lock.

## Đi từng bước qua một tình huống

Ở PostgreSQL Read Committed, các statement có snapshot theo quy tắc của mức đó; đọc lại trong cùng transaction có thể thấy commit mới. Repeatable Read giữ snapshot ổn định hơn nhưng không giải quyết mọi invariant kiểu write skew. Serializable nhằm làm kết quả tương đương một thứ tự transaction tuần tự và có thể abort một transaction để giữ tính chất đó.

## Hiểu cơ chế từ kết quả quan sát

Serializable không có nghĩa ứng dụng không phải xử lý lỗi. Serialization failure là tình huống phải retry cả transaction theo contract. Unique/check constraints và conditional updates vẫn là công cụ mạnh cho invariant cụ thể. Isolation name ở DB khác có thể có chi tiết khác; đối chiếu engine và version.

## Khái niệm và mô hình làm việc

Isolation nói transaction quan sát concurrent changes thế nào, không thay mọi business constraint.

## Cơ chế và những ranh giới cần giữ

Read Committed có snapshot mỗi statement; Repeatable Read giữ transaction snapshot nhưng có write skew; Serializable có thể abort và yêu cầu retry. PostgreSQL Read Uncommitted xử lý như Read Committed.

## Áp dụng vào hệ thống thật

Reservation invariant nhiều rows có thể cần serializable hoặc explicit locking/constraint.

## Những đường lỗi cần hiểu

Hai transactions cùng đọc điều kiện đúng rồi update rows khác làm invariant sai dưới snapshot isolation.

## Lần theo bằng chứng khi có sự cố

Dựng hai sessions với barriers để quan sát anomalies; đọc SQLSTATE 40001 và plans/locks.

## Đánh đổi và giới hạn sử dụng

Mạnh hơn tăng abort/cost; chọn từ invariant, không default nâng mọi query.

## Thực hành, debugging và kết luận

Dùng hai connection và barrier để ép timeline test; một test tuần tự không lộ anomaly. Đo lock waits, abort rate và latency khi tăng isolation. Chọn mức đủ bảo vệ yêu cầu, giữ transaction ngắn và giới hạn retries để contention không biến thành storm.


## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)
