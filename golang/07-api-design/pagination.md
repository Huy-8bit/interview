# Pagination: stable order và cursor

## Bài toán và ví dụ đầu tiên

Danh sách user tăng từ 100 lên một triệu. Trả tất cả rows làm query, memory và response tăng theo dữ liệu; pagination chia kết quả thành các phần có bound. Việc chia phải định nghĩa thứ tự ổn định và hành vi khi dữ liệu đổi giữa pages.

## Đi từng bước qua một tình huống

Offset pagination dễ hiểu: bỏ N rows rồi lấy limit. Với offset lớn có thể tốn nhiều công việc, và insert/delete trước vị trí hiện tại làm client thấy lặp hoặc bỏ sót. Keyset pagination dùng cursor như (created_at,id) để lấy các row sau vị trí đó theo total order có tie-breaker.

## Hiểu cơ chế từ kết quả quan sát

Cursor không là bằng chứng quyền truy cập. Decode/validate rồi vẫn áp tenant filter và authorization. Opaque cursor có thể chứa version/query parameters để phát hiện reuse sai filter; cần giới hạn page size và policy expiry nếu state thay đổi. Snapshot semantics mạnh hơn có chi phí riêng.

## Khái niệm và mô hình làm việc

Pagination cần order deterministic, bound page size và contract khi dữ liệu đổi giữa pages.

## Cơ chế và những ranh giới cần giữ

Keyset dùng (created_at,id) và index cùng thứ tự; cursor opaque có filter/version và integrity khi cần. Offset sâu tốn scan và dễ shift khi insert/delete.

## Áp dụng vào hệ thống thật

GET /orders?after=cursor&limit=100 theo tenant, authorization vẫn kiểm tra mỗi page.

## Những đường lỗi cần hiểu

Timestamp ties bỏ/duplicate rows; cursor từ tenant khác; client đổi filter giữa pages.

## Lần theo bằng chứng khi có sự cố

Fixtures với equal timestamps và concurrent inserts, EXPLAIN deep pages và query count.

## Đánh đổi và giới hạn sử dụng

Offset tiện nhảy page nhỏ; keyset hiệu quả nhưng không tự cho random page number.

## Thực hành, debugging và kết luận

Test nhiều rows cùng timestamp, insert giữa pages, delete và direction đổi. Xem query plan/index khớp filter+order. API nên nói có cần total count chính xác không vì COUNT có thể là query đắt riêng; không tính mặc định nếu product không dùng.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9110)
