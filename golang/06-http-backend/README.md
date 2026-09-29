# Http Backend

Bound HTTP resources, reuse pools và drain an toàn.

## Reading map

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

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
