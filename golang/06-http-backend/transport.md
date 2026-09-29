# Transport: pool owner

## Bài toán và ví dụ đầu tiên

Ứng dụng muốn reuse connections và kiểm soát TLS nhưng chỉ thấy http.Client. Transport là lớp thực hiện một HTTP round trip: tìm hoặc mở connection, nói protocol và trả response; Client bổ sung policy cấp cao như redirect.

## Đi từng bước qua một tình huống

Tạo một Transport dùng lâu dài, thường clone DefaultTransport để giữ cấu hình mặc định hợp lý rồi chỉnh field cần thiết trước khi dùng concurrent. Không mutate cấu hình tùy ý trong lúc requests đang chạy. Custom RoundTripper wrapper có thể thêm metrics nhưng phải giữ contract response/error và body ownership.

## Hiểu cơ chế từ kết quả quan sát

Pool nằm ở Transport nên hai Client chia sẻ Transport cũng chia sẻ việc reuse. Client với Transport nil dùng DefaultTransport, khác việc tạo một Transport zero-value mới cho mỗi call. HTTP/2 behavior với custom dial/TLS settings phụ thuộc cấu hình; kiểm tra protocol thực tế thay vì giả định.

## Khái niệm và mô hình làm việc

Transport là RoundTripper quản lý wire protocol, dialing và reusable connections.

## Cơ chế và những ranh giới cần giữ

Clone DefaultTransport giữ useful defaults; config trước khi share. Custom Dial/TLS settings có thể ảnh hưởng protocol negotiation nên xác nhận HTTP/2 thực tế.

## Áp dụng vào hệ thống thật

Dedicated transports cho dependency cần isolation/proxy/TLS policy khác nhau.

## Những đường lỗi cần hiểu

Transport mới mỗi call; custom proxy header trust sai; HTTP/2 bị vô hiệu ngoài dự kiến.

## Lần theo bằng chứng khi có sự cố

httptrace protocol, connection reuse, TLS handshake và FD metrics.

## Đánh đổi và giới hạn sử dụng

Không tạo transport riêng mỗi tenant khi tenant cardinality lớn trừ có lifecycle/limit rõ.

## Thực hành, debugging và kết luận

Nếu goroutine hoặc socket tăng, tìm nơi tạo Transport và body chưa Close. Đo reused connections, dial duration và in-flight calls. CloseIdleConnections giải phóng idle theo nhu cầu, không dừng mọi active request và không thay graceful shutdown hay request cancellation.



## Code: tạo Transport một lần và cấu hình trước khi phục vụ

```go
package outbound

import (
    "net/http"
    "time"
)

func NewClient() *http.Client {
    transport := http.DefaultTransport.(*http.Transport).Clone()
    transport.MaxIdleConns = 100
    transport.MaxIdleConnsPerHost = 20
    transport.MaxConnsPerHost = 40
    transport.IdleConnTimeout = 60 * time.Second
    transport.ResponseHeaderTimeout = 2 * time.Second
    return &http.Client{Transport: transport, Timeout: 5 * time.Second}
}
```

### Giải thích code từng bước

Clone tạo một Transport độc lập dựa cấu hình mặc định, rồi các field được chỉnh trước khi requests dùng concurrent. Type assertion giả định chương trình chưa thay biến http.DefaultTransport bằng một RoundTripper khác; trong code có thể thay global, cần kiểm tra assertion hoặc giữ dependency explicit. Những con số là ví dụ, không cấu hình chung cho mọi partner.

MaxIdleConns 100 và per-host 20 nói về connections đang rảnh giữ lại. MaxConnsPerHost 40 là trần connection theo host, khác request concurrency trong HTTP/2. Header timeout 2 giây giới hạn chờ headers theo contract; Client.Timeout 5 giây áp budget tổng operation của client. Caller vẫn tạo request với context có thể ngắn hơn, và phải đọc/Close body đúng.

Gọi NewClient một lần trong startup owner, inject pointer vào services rồi reuse. Nếu gọi trong mỗi handler, mỗi instance giữ pool riêng và reuse giữa requests mất đi. CloseIdleConnections khi shutdown/đổi topology theo policy chỉ tác động idle connections; active work cần deadline/cancel/drain riêng.

Để kiểm chứng, httptest server đếm connections hoặc httptrace đọc GotConn.Reused cho các calls liên tiếp, với body được consume đúng. Test khác gửi response body lớn hơn bound để biết policy đóng bỏ có thể hy sinh reuse. Khi benchmark, giữ protocol và TLS settings rõ: HTTP/1 sequential reuse không chứng minh behavior của hàng trăm HTTP/2 streams concurrent.

## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)

## Thực hành có điều kiện kiểm chứng

Tạo hai requests tuần tự tới httptest.Server và quan sát GotConn.Reused. So shared Transport với Transport mới mỗi call; đóng body tới EOF ở cả hai để không lẫn biến. Tiếp theo giữ body chưa đọc và xem request concurrency/pool behavior. Đây là controlled experiment cho reuse, không là benchmark network production hoặc HTTP/2 capacity.
