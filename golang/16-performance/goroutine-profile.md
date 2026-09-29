# Goroutine profiles và stack grouping

## Bài toán và ví dụ đầu tiên

Goroutine count từ 500 lên 20000 trong một giờ và không giảm sau traffic. Goroutine profile chụp stack để biết các công việc đang chạy hoặc chờ ở đâu.

## Đi từng bước qua một tình huống

Nhóm stack theo vị trí như chan send, SQL acquire, net read hay mutex. Hàng nghìn send ở cùng function gợi ý consumer đã rời; nhiều net read có thể là long-lived sessions hợp lệ. So creation site và owner lifetime trước khi gọi tất cả là leak.

## Hiểu cơ chế từ kết quả quan sát

Một ảnh chụp không cho duration đầy đủ; lấy các snapshot có khoảng cách và đối chiếu request/connection count. Waiting không chiếm CPU liên tục nhưng vẫn giữ stack và reachable data. Context cancel chỉ hữu ích nếu operation đang chờ quan sát nó.

## Khái niệm và mô hình làm việc

Snapshot cho thấy G đang chạy/chờ ở call stack nào; trend mới giúp phân biệt leak với concurrency hợp lệ.

## Cơ chế và những ranh giới cần giữ

Debug dump group by stack signature, state và creation site; strip volatile IDs khi aggregate.

## Áp dụng vào hệ thống thật

20k G phần lớn database/sql acquire: kiểm tra pool/DB hold time trước scheduler tune.

## Những đường lỗi cần hiểu

Stack dump quá lớn gây log volume; gọi mọi waiting G là leak.

## Lần theo bằng chứng khi có sự cố

Lấy ba snapshots trước/trong/sau drain, xem nhóm nào không giảm và owner đã exit.

## Đánh đổi và giới hạn sử dụng

Snapshot không cho duration chính xác; dùng trace/metrics để bổ sung timeline.

## Thực hành, debugging và kết luận

Test caller bỏ cuộc rồi chờ worker-owned finished signal. Trong incident, xác định đường exit/cancel/close và sửa protocol thay vì chỉ tăng memory. Count tuyệt đối không là invariant chung vì runtime và libraries có goroutine nền hợp lệ.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](pprof.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://go.dev/doc/diagnostics)
