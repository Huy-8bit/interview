# HTTP request lifecycle

## Bài toán và ví dụ đầu tiên

Client báo endpoint mất 2 giây nhưng timing trong service chỉ 100 ms. Phần còn lại có thể ở DNS/TLS, đọc body, middleware, pool wait hoặc write response. Lifecycle là toàn chuỗi từ nhận kết nối đến trả tài nguyên, giúp đo đúng phần đang mất thời gian.

## Đi từng bước qua một tình huống

Theo GET users: connection được nhận, headers parse, mux chọn handler, auth kiểm tra, service lấy DB connection, query chạy, rows được đọc, response encode rồi ghi. Mỗi bước có lỗi và owner cleanup; query đã xong chưa có nghĩa connection đã được trả nếu Rows còn giữ.

## Hiểu cơ chế từ kết quả quan sát

Context đi cùng request xuống dependency; response writer chỉ có lifetime trong ServeHTTP. Sau return, công việc nền muốn tồn tại phải có owner khác. Các span chỉ ghi DB execute có thể bỏ mất acquire wait, nên trace cần các biên phù hợp để tổng thời gian giải thích được latency client.

## Khái niệm và mô hình làm việc

Request đi qua network, middleware, handler, dependencies rồi response cleanup.

## Cơ chế và những ranh giới cần giữ

Middleware order thường recovery/trace, auth, admission rồi business handler; order cụ thể phụ thuộc error/security contract. Context đi xuyên chain.

## Áp dụng vào hệ thống thật

Measure tổng duration và dependency spans; inbound body bounded, outbound body closed.

## Những đường lỗi cần hiểu

Middleware đọc hết body rồi handler không còn input; status đã commit trước khi error mapper chạy.

## Lần theo bằng chứng khi có sự cố

Correlate route template, status và spans; kiểm tra middleware wrappers preserve interfaces cần thiết.

## Đánh đổi và giới hạn sử dụng

Đừng ghi raw URL/query làm label vì cardinality và PII.

## Thực hành, debugging và kết luận

Khi debug, đối chiếu timestamp client/server và trace theo request ID, xem percentile cùng route/status. Client chậm đọc body gây write wait, payload lớn gây encode allocation; hai trường hợp cần profile khác. Giữ giới hạn input/output và cleanup ở từng boundary.


## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)

## Thực hành có điều kiện kiểm chứng

Vẽ riêng ba timelines: client disconnect trước DB acquire, disconnect khi query chạy, disconnect sau commit trước response. Cả ba có thể báo context error ở client nhưng durable outcomes khác nhau. Test handler không dùng ResponseWriter từ background G sau return. Request body được server cleanup không cho phép bỏ qua body limits hoặc decode errors trong handler.
