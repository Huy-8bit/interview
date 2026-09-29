# HTTP từ kết nối đến response và shutdown

Module bắt đầu TCP/request/handler, rồi mới mở rộng keep-alive, Client, Transport và pools. Mỗi pha có resource owner và timeout khác nhau; hiểu pha giúp debug connection churn hoặc P99 cao mà không đổi mọi timeout cùng lúc. Cuối module ghép lifetime request với signal/drain của process.

## Bắt đầu và cách thực hành

Bắt đầu với [net-http](net-http.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [HTTP connection pools và capacity budget](connection-pooling.md) | P0 |
| [Graceful shutdown và dependency order](graceful-shutdown.md) | P0 |
| [HTTP performance có evidence](high-performance-http.md) | P1 |
| [HTTP client reuse và response ownership](http-client.md) | P0 |
| [HTTP server configuration](http-server.md) | P1 |
| [Keep-alive: HTTP reuse và TCP liveness](keep-alive.md) | P1 |
| [Middleware và interface preservation](middleware.md) | P1 |
| [net/http: server, handler và request lifetime](net-http.md) | P0 |
| [HTTP request lifecycle](request-lifecycle.md) | P1 |
| [HTTP timeout layers](timeout.md) | P1 |
| [Transport: pool owner](transport.md) | P1 |
| [WebSocket: long-lived connection lifecycle](websocket.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
