# Middleware và interface preservation

## Bài toán và ví dụ đầu tiên

Mọi endpoint cần request ID, auth và metrics. Copy cùng code vào handler dễ lệch behavior khi sửa. Middleware là hàm bao một Handler để chạy logic trước hoặc sau lời gọi handler tiếp theo.

## Đi từng bước qua một tình huống

Nếu chain là metrics(auth(handler)), metrics quan sát cả request bị auth từ chối. Nếu auth(metrics(handler)), những request bị chặn có thể không vào metrics bên trong. Thứ tự là behavior của sản phẩm và observability, không chỉ thẩm mỹ. Recovery cũng chỉ bao những phần nằm bên trong nó.

## Hiểu cơ chế từ kết quả quan sát

Wrapper ResponseWriter muốn ghi status/bytes phải giữ đúng interface behavior mà downstream cần, như streaming/flushing khi thích hợp. Ghi body để log toàn bộ có thể tiêu memory và lộ secret. Context values phù hợp request metadata nhưng không nên dùng để giấu DB dependency.

## Khái niệm và mô hình làm việc

Middleware wrap Handler để xử lý concern xuyên endpoints với ordering rõ.

## Cơ chế và những ranh giới cần giữ

Record status mặc định 200 và bytes; không gọi WriteHeader lần hai. Wrapper cần preserve Flusher/Hijacker hoặc hỗ trợ Unwrap/ResponseController theo yêu cầu.

## Áp dụng vào hệ thống thật

Auth principal vào context, metrics label route template, recovery log stack bounded.

## Những đường lỗi cần hiểu

Response recorder wrapper phá WebSocket/streaming; log token; middleware retry response đã partial.

## Lần theo bằng chứng khi có sự cố

httptest cho order, panic trước/sau header, flush và hijack behavior.

## Đánh đổi và giới hạn sử dụng

Không đặt business transaction logic tùy endpoint vào global middleware mơ hồ.

## Thực hành, debugging và kết luận

Test một request success, auth failure, panic và streaming nếu hỗ trợ. Kiểm tra status ghi lần đầu và duration có bao gồm dependency wait. Middleware nên giữ công việc ngắn; một call network xác thực không deadline ở đầu chain có thể làm mọi endpoint chậm dù handler tốt.


## Đọc tiếp

- [net/http: server, handler và request lifetime](net-http.md)
- [HTTP client reuse và response ownership](http-client.md)
- [design-high-throughput-api](../13-system-design/design-high-throughput-api.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://pkg.go.dev/net/http)

## Thực hành có điều kiện kiểm chứng

Viết test chain trace→auth→handler và assert unauthorized request không vào business handler. Sau đó dùng streaming handler gọi Flush qua wrapper; ResponseRecorder-only test không đủ chứng minh WebSocket hijack. Recorder phải ghi status chỉ một lần và giữ bytes count khi Write trả partial/error. Middleware timing cần nói rõ có gồm response body streaming toàn bộ hay chỉ setup.
