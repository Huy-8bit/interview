# PostgreSQL với Go

## Bài toán và ví dụ đầu tiên

Một order service cần lưu đơn và reserve stock trong PostgreSQL. Bài toán đầu tiên là giữ invariant durable và hiểu type/lifetime của query, trước khi chọn ORM hay tối ưu driver. PostgreSQL cung cấp transaction và constraints; Go code phải dùng chúng tại đúng biên.

## Đi từng bước qua một tình huống

Tạo order và cập nhật stock trong cùng transaction, dùng tham số cho user input và kiểm tra affected rows của conditional stock update. Không giữ transaction mở trong lúc gọi payment qua mạng; đó là boundary phân tán cần workflow riêng. Timestamp, numeric money và nullable fields cần mapping rõ để không mất ý nghĩa khi Scan.

## Hiểu cơ chế từ kết quả quan sát

MVCC giữ các phiên bản dữ liệu để transaction đọc theo isolation semantics; nó không tự bảo vệ mọi check-then-act. Index tăng tốc access pattern phù hợp nhưng cũng tăng chi phí ghi. Cancellation từ ctx đi qua driver; statement_timeout phía server có thể bổ sung giới hạn thực thi theo policy.

## Khái niệm và mô hình làm việc

Go client cần contract về types, transactions, cancellation và schema evolution.

## Cơ chế và những ranh giới cần giữ

Use parameterized SQL, scan nullable fields vào explicit nullable types/pointers, UTC/time semantics rõ và numeric types không mất precision. Migration expand-contract phối hợp rolling versions.

## Áp dụng vào hệ thống thật

Insert idempotency key + domain state + outbox trong một transaction.

## Những đường lỗi cần hiểu

Float64 dùng cho money; timestamp timezone sai; app version mới yêu cầu column trước migration.

## Lần theo bằng chứng khi có sự cố

Integration tests trên PostgreSQL thật đúng major; log SQLSTATE/query name thay raw sensitive parameters.

## Đánh đổi và giới hạn sử dụng

Postgres features tốt nhưng tăng vendor coupling; dùng khi invariant/query benefits rõ.

## Thực hành, debugging và kết luận

Production cần pg_stat_activity, lock waits và query plans bên cạnh DB.Stats phía Go. Dùng EXPLAIN với thận trọng: ANALYZE thực thi query, đặc biệt lưu ý write. Integration test schema/query thật và migration rolling-compatible; một mock repository không kiểm chứng được SQL type hoặc transaction isolation.



## Một transaction cụ thể và hai request tranh cùng hàng

Giả sử stock(product_id, available) có10 sản phẩm, request A và B đều muốn mua7. Read available rồi kiểm tra trong Go không đủ: cả hai có thể đọc10 trước khi ai ghi. Một conditional update trong transaction với điều kiện available>=7 cho database quyết định theo concurrency semantics của nó; caller kiểm tra affected rows để biết reservation có thành công. Order record và reservation liên quan cần commit cùng boundary nếu invariant yêu cầu.

Trong Go, BeginTx thành công trả Tx giữ một connection. Mọi statements của operation phải dùng Tx; defer rollback để đường lỗi cleanup, rồi Commit tại điểm đầy đủ điều kiện. Nếu ExecContext trả lỗi hoặc affected rows không đạt, không tiếp tục tạo order success. Nếu Commit trả lỗi mất kết nối, outcome có thể chưa rõ từ caller; query theo operation ID và constraint durable giúp xác định lại thay vì mặc định tạo order mới.

Null trong SQL không chỉ là zero value Go. Một nullable deleted_at cần biểu diễn có/không có giá trị bằng type phù hợp; zero time không mặc nhiên là “không xóa”. Numeric money cần units/currency và precision policy, tránh float roundoff vô ý. Schema đổi nullable hoặc type mà generated Go code chưa cập nhật có thể chỉ lỗi ở Scan runtime, nên integration test với migrations thật quan trọng.

Query performance cũng cần workload thật: index cho product_id giúp tìm hàng, nhưng một sản phẩm cực hot vẫn serialize updates cùng row. Tăng pool có thể thêm waiters chứ không thêm throughput. Xem lock waits và transaction hold time, không chỉ EXPLAIN trên một request đơn. Server statement_timeout và caller context bổ sung giới hạn, nhưng không thay operation identity khi response mất sau commit.

Bài lab SQL hiện không có PostgreSQL container/driver integration được dựng sẵn; các snippets compile giúp kiểm tra Go API và cleanup shape. Khi áp dụng, chạy test hai transactions điều phối cạnh tranh hàng, cancel khi pool wait và migration old/new compatibility trên DB version mục tiêu. Ghi rõ kết quả chưa đo thay vì dùng unit mock để tuyên bố transaction semantics đã được chứng minh.

## Đọc tiếp

- [database/sql: pool handle, rows và transaction ownership](database-sql.md)
- [Database connection pool: 500 requests và 20 connections](database-sql-pool.md)
- [outbox-pattern](../12-distributed-systems/outbox-pattern.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/database/)
