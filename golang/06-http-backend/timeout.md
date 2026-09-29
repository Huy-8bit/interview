# HTTP timeout layers

## Bài toán và ví dụ đầu tiên

Một TCP dial timeout 1 giây không ngăn server giữ connection đã nối mà không bao giờ trả body. HTTP có nhiều pha, mỗi timeout chỉ che một phần. Thiết kế bắt đầu từ deadline tổng và các giới hạn pha để biết đang bảo vệ điều gì.

## Đi từng bước qua một tình huống

Tách DNS/dial/TLS, chờ headers và đọc body. Client.Timeout bao phủ operation theo contract Client, context có thể ngắn hơn; ResponseHeaderTimeout không tự giới hạn toàn bộ đọc body. Ở server, ReadHeaderTimeout giúp với client gửi header chậm nhưng không thay body limit và nghiệp vụ deadline.

## Hiểu cơ chế từ kết quả quan sát

Timeout làm caller ngừng chờ; remote server có thể đã commit một mutation. Đối với retry, cần phân loại operation và idempotency, không chỉ nhìn error timeout. Streaming cần lifetime dài nhưng vẫn cần policy phát hiện không tiến triển, thay vì một timeout tổng vài giây dùng cho mọi route.

## Khái niệm và mô hình làm việc

Deadline tổng khác timeout từng network phase.

## Cơ chế và những ranh giới cần giữ

Client.Timeout gồm body read; Dial timeout cho kết nối, TLSHandshakeTimeout cho TLS, ResponseHeaderTimeout cho headers, IdleConnTimeout cho idle sockets. Server timeout không kill arbitrary Go work.

## Áp dụng vào hệ thống thật

Budget 200 ms chia admission/connect/dependency/serialize với headroom; từng hop lấy remaining parent deadline.

## Những đường lỗi cần hiểu

Timeout retry không idempotent tạo duplicate; header nhận nhanh nhưng body chậm vượt budget.

## Lần theo bằng chứng khi có sự cố

httptrace và request spans tách pool wait/connect/TTFB/body; errors.Is context deadline với wrapped errors.

## Đánh đổi và giới hạn sử dụng

Streaming không hợp total timeout ngắn; cần idle/progress policy riêng.

## Thực hành, debugging và kết luận

Dùng test server trì hoãn từng pha để xác nhận field cấu hình thực sự có hiệu lực nơi mong muốn. Trong incident, httptrace phân connect/TLS/first-byte; goroutine stack giúp thấy read body chờ. Tăng timeout chỉ khi latency đó hợp lệ và capacity chịu được số request tồn tại lâu hơn.


## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)

## Thực hành có điều kiện kiểm chứng

Experiment server trả headers sau 20 ms rồi body sau2s; client timeout500 ms phải fail trong body read dù header timeout 100 ms không hết. Test khác giữ connection cap 1 và occupy slot: request thứ hai có thể hết budget trước dial. Dùng httptrace để phân biệt acquisition wait với remote first-byte latency, rồi size concurrency theo evidence thay tăng mọi timeout.
