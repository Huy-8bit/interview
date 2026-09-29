# Object lifecycle và resource ownership

## Bài toán và ví dụ đầu tiên

Một Rows object cuối cùng không còn ai tham chiếu, nhưng connection pool đã cạn trước khi GC chạy. Memory lifetime và resource lifetime khác nhau: GC có thể thu memory nhưng ứng dụng vẫn phải trả tài nguyên khan hiếm ở thời điểm xác định.

## Đi từng bước qua một tình huống

Sau QueryContext thành công, owner defer rows.Close rồi iterate và kiểm tra rows.Err. Với transaction, đặt rollback cleanup ngay sau Begin thành công và Commit tại điểm nghiệp vụ hoàn tất. Với HTTP response, đọc theo chính sách size rồi Close body. Với worker, cancel yêu cầu dừng và join xác nhận đã trả tài nguyên.

## Hiểu cơ chế từ kết quả quan sát

Acquire là lúc nhận quyền sử dụng, release là trả quyền đó. Mỗi tài nguyên cần một owner chịu trách nhiệm release trên cả success/error. Chuyển pointer qua nhiều hàm không tự chuyển ownership; API phải nói caller hay callee Close. Finalizer hoặc GC không phải cơ chế deterministic cleanup cho connection và descriptor.

## Khái niệm và mô hình làm việc

Object lifetime kết thúc khi không reachable; resource lifetime kết thúc khi owner Close/Stop đúng protocol.

## Cơ chế và những ranh giới cần giữ

Channel/closure/cache có thể kéo dài object life vượt stack frame. Finalizer timing không phù hợp để release connection cần prompt cleanup.

## Áp dụng vào hệ thống thật

DB rows close ở scope đọc; HTTP response body close ngay sau consume; worker cancel rồi join.

## Những đường lỗi cần hiểu

Unclosed rows giữ pool slot dù object cuối cùng có thể được GC; cancellation không được awaited.

## Lần theo bằng chứng khi có sự cố

Lập bảng acquire-owner-release cho request; profile references và theo dõi FD/pool metrics.

## Đánh đổi và giới hạn sử dụng

Explicit cleanup dài hơn chút nhưng deterministic; không dựa GC để giữ SLO tài nguyên.

## Thực hành, debugging và kết luận

Trong incident, lập đường đi acquire→owner→release cho từng tài nguyên đang cạn. Test lỗi ngay sau acquire và lỗi giữa vòng đọc. Cleanup timeout riêng có thể cần cho shutdown nhưng phải hữu hạn; không giải quyết leak bằng cách chờ GC ngẫu nhiên.


## Đọc tiếp

- [Garbage collection: live heap, pacing và memory budget](garbage-collector.md)
- [Escape analysis: đọc quyết định của compiler](escape-analysis.md)
- [memory-profile](../16-performance/memory-profile.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/gc-guide)
