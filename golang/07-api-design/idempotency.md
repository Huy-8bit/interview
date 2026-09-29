# API idempotency key

## Bài toán và ví dụ đầu tiên

Hai lần nhấn nút tạo order có thể sinh hai HTTP requests với cùng ý định. Idempotency ở API cần giúp client diễn đạt chúng là cùng operation hoặc hai operation khác, không đoán bằng payload giống nhau trong vài giây.

## Đi từng bước qua một tình huống

Client tạo key trước attempt đầu, server lưu key theo tenant/operation cùng request fingerprint. Cùng key và cùng input trả kết quả đã biết hoặc pending; cùng key nhưng input khác là conflict. Unique durable claim xử lý hai attempts đến đồng thời, không chỉ cache in-memory.

## Hiểu cơ chế từ kết quả quan sát

Nếu order và dedup state cùng DB, commit chúng trong cùng transaction. Khi effect ở partner bên ngoài, giữ provider reference và workflow unknown/reconcile. TTL của key phải phù hợp retry window, nếu không retry cũ sau expiry thành đơn mới.

## Khái niệm và mô hình làm việc

Idempotency bảo đảm replay cùng logical operation không tạo side effect thêm theo contract/retention window.

## Cơ chế và những ranh giới cần giữ

Scope key theo tenant+operation; lưu request hash, state và stable response trong durable store. Unique constraint claim; key trùng payload khác trả conflict.

## Áp dụng vào hệ thống thật

Payment creation lưu operation trước provider call và dùng cùng provider key; reconcile ambiguous outcome.

## Những đường lỗi cần hiểu

Redis TTL hết trước retry; cache response chỉ sau side effect để lại crash window; hai replicas cùng xử lý key.

## Lần theo bằng chứng khi có sự cố

Trace logical operation ID và attempts; inject crash giữa claim, effect, response persistence.

## Đánh đổi và giới hạn sử dụng

Storage retention có cost; không cache mọi 500 vĩnh viễn nếu contract cho retry sau recovery.

## Thực hành, debugging và kết luận

Test concurrency, crash windows và expiry. Theo dõi duplicate hits cùng conflict khác payload, bảo vệ response đã lưu theo permission. Contract phải nói rõ key scope, retention và response cho operation đang chạy để client có thể phục hồi đúng.


## Đọc tiếp

- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)
- [idempotency](../12-distributed-systems/idempotency.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.rfc-editor.org/rfc/rfc9110)
