# Distributed idempotency và ambiguous outcomes

## Bài toán và ví dụ đầu tiên

Client gửi POST /payments, server charge thành công nhưng response bị mất. Client retry không biết mình đang yêu cầu charge lần đầu hay lần thứ hai. Idempotency giải quyết việc nhiều attempts của cùng một thao tác nghiệp vụ tạo cùng hiệu quả cuối theo contract, dù mạng và process có thể lỗi giữa chừng.

## Đi từng bước qua một tình huống

Client tạo operation key K trước attempt đầu và giữ K khi retry. Server lưu K cùng fingerprint của request và trạng thái xử lý. Nếu cùng K nhưng amount hoặc recipient khác, server từ chối conflict; không trả bừa kết quả cũ cho một payload mới. Nếu K đã hoàn tất, trả kết quả đã lưu hoặc representation tương đương theo API. Nếu K đang xử lý, policy có thể cho chờ hữu hạn, trả pending hoặc conflict có hướng dẫn retry.

Hai attempts đồng thời đều chưa thấy K là tình huống phải giải quyết ở durable store. Unique constraint hoặc atomic insert chọn owner cho K; một check-then-insert không khóa/constraint sẽ cho cả hai vào. Nếu side effect nằm trong cùng DB, lưu dedup record và cập nhật nghiệp vụ trong cùng transaction giúp tránh một bên commit mà bên kia chưa ghi.

## Hiểu cơ chế từ kết quả quan sát

Nếu side effect là gọi ngân hàng bên ngoài, transaction DB local không thể atomic với ngân hàng chỉ nhờ bọc code trong Begin/Commit. Cần truyền cùng provider idempotency key nếu có, ghi trạng thái workflow và đối soát outcome. Crash sau remote commit nhưng trước local update là cửa sổ phải được mô hình hóa thành pending/unknown, không tự chuyển failed rồi tạo charge mới.

Idempotency key có scope, ví dụ tenant + endpoint + operation ID, để tránh collision xuyên người dùng. Retention phải dài hơn retry/replay window đã cam kết; xóa key quá sớm làm một retry cũ thành operation mới. Lưu response có thể chứa dữ liệu nhạy cảm nên cần policy access/retention tương ứng. Request fingerprint nên được định nghĩa trên dữ liệu canonical mà nghiệp vụ so sánh, không dựa tùy tiện vào thứ tự key JSON.

Idempotent không có nghĩa response bytes luôn giống nhau ở mọi API; nghĩa chính xác phải được viết ra. Cũng không có nghĩa mỗi attempt không làm gì: server có thể kiểm tra DB, log và cập nhật timestamp, miễn effect nghiệp vụ được giữ theo contract. Rate limiting vẫn cần vì retries duplicate vẫn tiêu tài nguyên.

## Khái niệm và mô hình làm việc

Retry cùng operation identity cần tạo effect tương đương một lần theo contract, kể cả response bị mất.

## Cơ chế và những ranh giới cần giữ

Durable key+request hash+state, unique constraint, transactional effect; external provider cần stable key và reconciliation. Dedup retention phải phủ replay horizon.

## Áp dụng vào hệ thống thật

Create payment operation pending, call provider với operation ID, persist outcome; recovery query provider khi timeout.

## Những đường lỗi cần hiểu

Crash sau effect trước response, expiry sớm, key reuse payload khác, concurrent attempts.

## Lần theo bằng chứng khi có sự cố

Inject crash tại các boundaries; compare ledger/provider/state bằng operation ID.

## Đánh đổi và giới hạn sử dụng

Exactly-once claim chỉ có ý nghĩa trong boundary cụ thể; external effects thường cần idempotency và reconcile.

## Thực hành, debugging và kết luận

Test ba điểm crash: trước claim K, sau local effect commit và sau remote effect trước local finalize. Test hai calls đồng thời cùng K/payload, cùng K/khác payload và retry sau expiry. Assert durable invariant, không chỉ HTTP status. Với consumer, dedup marker và effect cùng transaction là ứng dụng tương tự.

Trong incident double charge, tập hợp attempts theo operation key và provider reference; đừng chỉ nhìn request ID vì mỗi attempt có request ID khác. Mitigate bằng ngừng tạo identity mới khi retry, đối soát remote state và xử lý compensation theo business policy. Idempotency thêm storage và state machine, nhưng giúp biến lỗi mạng không rõ outcome thành quy trình phục hồi có thể kiểm soát.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)
