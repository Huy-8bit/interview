# Netpoller và network readiness

## Bài toán và ví dụ đầu tiên

Một server giữ 20000 socket nhưng đa số client chưa gửi gì. Không cần một thread chỉ đứng chờ mỗi socket. Netpoller kết nối cơ chế thông báo I/O của OS với goroutine đang cần tiếp tục read/write.

## Đi từng bước qua một tình huống

Goroutine gọi read trên socket runtime quản lý. Nếu chưa có dữ liệu, đường nonblocking báo chưa tiến triển được và runtime park goroutine. OS báo socket ready; runtime làm goroutine runnable, scheduler cho chạy khi có tài nguyên, rồi read tiếp. Ready chưa chắc có đủ một JSON message; parser còn phải theo framing.

## Hiểu cơ chế từ kết quả quan sát

Park nghĩa là giữ trạng thái chờ mà không chạy một vòng polling ở application. epoll/kqueue hoặc cơ chế tương ứng phụ thuộc OS; đây là runtime implementation, không phải caller tự chọn một thread riêng. File I/O, DNS qua cgo hoặc thư viện native có thể đi đường khác, nên không suy mọi I/O đều giải phóng M giống network socket.

## Khái niệm và mô hình làm việc

Netpoller nối OS readiness notifications với runnable goroutines, không xử lý business request thay application.

## Cơ chế và những ranh giới cần giữ

Nonblocking read chưa có bytes thì G park; readiness hoặc deadline wake G để retry operation. Backend phụ thuộc OS, ví dụ kqueue trên macOS.

## Áp dụng vào hệ thống thật

Một HTTP client chia sẻ Transport quản lý nhiều connections trong khi G chờ response.

## Những đường lỗi cần hiểu

DNS/cgo hoặc disk I/O bị nhầm là netpoll; socket không deadline giữ request buffers lâu.

## Lần theo bằng chứng khi có sự cố

Goroutine stack net/http + internal/poll, httptrace DNS/connect/first-byte và socket metrics xác định nơi chờ.

## Đánh đổi và giới hạn sử dụng

Readiness không bảo đảm đủ toàn bộ message; parser cần framing và deadline.

## Thực hành, debugging và kết luận

Khi CPU thấp mà request chậm, xem goroutine stack internal/poll rồi dùng httptrace phân DNS, connect, TLS và first byte. Thiếu deadline có thể giữ goroutine và request data lâu dù netpoller hoạt động đúng. Tối ưu scheduler không sửa downstream chưa gửi response.



## Từ Read tới parser: vì sao ready chưa có nghĩa request hoàn chỉnh

Giả sử client gửi phần đầu HTTP request rồi dừng200 ms trước phần tiếp theo. Goroutine server đọc được những bytes đầu, parser biết message chưa đủ nên tiếp tục Read. Khi chưa có bytes, runtime có thể park goroutine đang dùng socket này. Thread không cần đứng chờ riêng nó; các request khác vẫn có thể được xử lý nếu CPU và tài nguyên còn đủ.

Khi bytes mới tới, thông báo OS làm goroutine có thể runnable. Nó vẫn phải được scheduler chọn trước khi parser tiếp tục; đây là khoảng khác với network wait. Read có thể trả một phần dữ liệu, EOF hoặc lỗi, nên code ứng dụng cần framing và error handling. Một TCP packet không tương ứng đúng một JSON object hoặc một message nghiệp vụ.

Nếu client không bao giờ gửi phần còn lại và không có read/deadline policy thích hợp, goroutine có thể chờ rất lâu mà netpoller vẫn làm đúng chức năng. Request/connection giữ buffer, parser state và descriptor. Deadline bảo vệ lifetime, body/header limits bảo vệ lượng dữ liệu; netpoller chỉ tối ưu cách chờ I/O, không quyết định traffic nào nên được nhận.

Dùng test server/client loopback có channel điều phối thời điểm gửi từng phần để quan sát behavior. Execution trace cho timeline park/runnable, còn httptrace ở client chia các pha connection/first-byte. Không dùng Sleep để khẳng định server đã đọc một phần; một tín hiệu test hoặc quan sát protocol cụ thể mới tạo điều kiện đã biết. Phân biệt network socket runtime quản lý với file/DNS/native calls trước khi suy thread count từ số goroutine waiting.

## Đọc tiếp

- [Go scheduler: G, M, P và các đường blocking](scheduler-gmp.md)
- [trace](../16-performance/trace.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://github.com/golang/go/blob/go1.26.4/src/runtime/proc.go)
