# WebSocket: long-lived connection lifecycle

## Bài toán và ví dụ đầu tiên

Chat cần server gửi message ngay khi có sự kiện mà không đợi client tạo một HTTP request mới. WebSocket nâng cấp sang session hai chiều dài hạn, nên lifetime và backpressure khác endpoint JSON ngắn.

## Đi từng bước qua một tình huống

Một client chậm đọc khiến outbound queue của session đầy. Nếu fanout cứ append vô hạn, một user có thể giữ rất nhiều memory. Đặt cap theo bytes/count, deadline cho writes và policy disconnect hoặc drop chỉ những event ephemeral được phép mất. Message durable vẫn cần history để replay.

## Hiểu cơ chế từ kết quả quan sát

Read/write concurrency phụ thuộc contract library đang dùng; không tự tạo nhiều writer cùng connection. Heartbeat phát hiện session không tiến triển theo policy, không bảo đảm user thực sự đọc message. Khi reconnect, client gửi cursor và server replay từ durable history trước khi nối live stream theo boundary chống gap.

## Khái niệm và mô hình làm việc

WebSocket là duplex session sống lâu hơn HTTP request thông thường sau upgrade.

## Cơ chế và những ranh giới cần giữ

Registry quản lý connections, bounded outbound queue mỗi client, ping/pong deadline và single-writer protocol theo library. Shutdown HTTP không tự drain hijacked sessions.

## Áp dụng vào hệ thống thật

Chat disconnect slow consumer, resume bằng durable message sequence.

## Những đường lỗi cần hiểu

Broadcast goroutine per message/client tạo explosion; slow client giữ unbounded queue; reconnect storm.

## Lần theo bằng chứng khi có sự cố

Connection count, queue bytes/age, ping failures và send-block stacks; test network half-open.

## Đánh đổi và giới hạn sử dụng

Không dùng websocket khi polling/SSE đáp ứng một chiều đơn giản hơn; library-specific concurrency phải đọc docs.

## Thực hành, debugging và kết luận

Server.Shutdown không tự quản lý hijacked WebSocket; cần registry session để stop và join. Test slow consumer, disconnect giữa send và reconnect duplicate. Metrics active sessions, queue age/bytes, close reason và replay gaps giúp phân biệt network churn với lỗi fanout.


## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)
