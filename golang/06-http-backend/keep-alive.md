# Keep-alive: HTTP reuse và TCP liveness

## Bài toán và ví dụ đầu tiên

Một client gọi API mỗi 100 ms. Tạo TCP/TLS connection mới cho từng call lặp lại handshake không cần thiết. HTTP keep-alive cho nhiều request dùng lại connection nếu protocol và hai đầu cho phép.

## Đi từng bước qua một tình huống

Với HTTP/1, call đầu đọc response body tới EOF rồi Close; call sau có thể được Transport lấy connection idle đó. Nếu body bỏ dở, reuse có thể không xảy ra. HTTP/2 còn multiplex streams, nên đếm connection không trực tiếp cho biết có bao nhiêu request đang hoạt động.

## Hiểu cơ chế từ kết quả quan sát

TCP keepalive là probe ở tầng TCP để hỗ trợ phát hiện peer chết trong một số tình huống; nó không giới hạn latency nghiệp vụ và không thay request timeout. HTTP idle timeout cũng là policy khác. Nhiều lớp proxy có thời hạn idle riêng nên connection có thể đóng dù application muốn reuse.

## Khái niệm và mô hình làm việc

HTTP keep-alive là reuse connection; TCP keepalive là probes phát hiện peer chết ở tầng TCP.

## Cơ chế và những ranh giới cần giữ

HTTP/1 reuse cần protocol/body cleanup hợp lệ; server/client/LB có idle policies khác nhau. HTTP/2 multiplex streams trên long-lived connection.

## Áp dụng vào hệ thống thật

Giảm connect/TLS CPU bằng reuse nhưng rotate connections khi lifecycle/DNS/routing yêu cầu.

## Những đường lỗi cần hiểu

Nhầm TCP KeepAlive với request timeout; stale connections sau LB idle expiration.

## Lần theo bằng chứng khi có sự cố

Đo reused ratio, reset/EOF errors sau idle và server Connection headers.

## Đánh đổi và giới hạn sử dụng

Disable keep-alive thường tăng latency/load; chỉ dùng khi protocol/isolation thực sự yêu cầu.

## Thực hành, debugging và kết luận

Dùng httptrace để nhìn GotConn.Reused và thời gian connect/TLS, đối chiếu body cleanup. Nếu dial rate tăng sau release, xem lifecycle Transport và response body trước khi tăng mọi timeout. Giữ idle lâu đổi ít handshake lấy nhiều socket; đo theo traffic pattern thực.


## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)
