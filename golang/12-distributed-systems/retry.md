# Retries như một capacity policy

## Bài toán và ví dụ đầu tiên

Một dependency thỉnh thoảng trả 503 trong 50 ms khi failover. Retry có thể biến lỗi tạm thời thành thành công. Nhưng nếu dependency đang quá tải kéo dài, mọi caller retry ngay sẽ tăng tải đúng lúc capacity giảm. Vì vậy retry là thêm công việc có điều kiện, không là cách chữa lỗi miễn phí.

## Đi từng bước qua một tình huống

Giả sử ba tầng đều cho tối đa ba attempts. Một request đầu vào có thể gây tới 27 attempts ở tầng cuối trong một số call graphs. Để tránh khuếch đại, chọn nơi sở hữu retry, đặt total deadline và retry budget. Budget có thể giới hạn số attempt thêm so với traffic gốc; hết budget thì trả lỗi có quan sát rõ.

Exponential backoff tăng khoảng chờ giữa attempts, ví dụ theo hệ số tăng có trần. Jitter thêm lệch ngẫu nhiên để nhiều caller không thức dậy đúng cùng mốc. Khoảng chờ phải quan sát ctx.Done; một sleep không hủy được giữ goroutine sau khi request đã hết quyền chờ. Những con số cụ thể cần chọn từ latency mục tiêu và behavior dependency.

## Hiểu cơ chế từ kết quả quan sát

Phân loại lỗi trước: input sai, không đủ quyền hoặc schema không tương thích không tự hết bằng retry. Timeout và connection reset có thể là transient nhưng còn unknown outcome với mutation. Retry chỉ an toàn khi operation đọc/replay-safe hoặc có idempotency contract đúng. Retry GET vẫn có load cost và không nên thử vô hạn.

Mỗi attempt dùng phần budget còn lại, không tạo Background với timeout mới. Giữ response/body cleanup trước attempt sau để không cạn connection. Nếu API trả Retry-After, xem contract của nó cùng deadline và policy client. Circuit breaker có thể chặn attempts tới dependency đang lỗi; breaker không thay timeout hay idempotency.

## Khái niệm và mô hình làm việc

Retry dùng additional attempts để tăng success cho transient errors nhưng tăng load khi hệ thống yếu.

## Cơ chế và những ranh giới cần giữ

Backoff+jitter, attempts cap, total deadline và retry budget theo logical requests; classify permanent/transient và side-effect safety.

## Áp dụng vào hệ thống thật

Retry read timeout trong remaining budget; mutation chỉ replay khi có key/invariant.

## Những đường lỗi cần hiểu

Layered retries nhân traffic; clients cùng retry khi dependency recover; cancellation không interrupt sleep.

## Lần theo bằng chứng khi có sự cố

Attempts/success ratio, retry wait histogram và cause categories; test total wall time.

## Đánh đổi và giới hạn sử dụng

Không retry để che overload; circuit/admission/load shedding có thể cần trước.

## Thực hành, debugging và kết luận

Production cần metric attempts, original requests, retry success và final failure riêng. Một tỷ lệ success cao có thể che việc chi phí đã tăng gấp ba và làm P99 xấu. Khi outage, giảm retry load, shed work không thiết yếu và xác nhận recovery bằng completion rate, không chỉ số lỗi transport giảm.

Test bằng dependency fake có chuỗi lỗi rồi success, lỗi permanent, cancellation trong backoff và response bị mất sau effect. Với mutation, kiểm tra cùng operation ID qua mọi attempt. Trade-off là thêm latency và load để đổi xác suất thành công; quyết định dựa giá trị công việc và capacity còn lại.


## Đọc tiếp

- [Idempotent consumer transaction](../10-messaging/idempotent-consumer.md)
- [system-design-framework](../13-system-design/system-design-framework.md)
- [HTTP client reuse và response ownership](../06-http-backend/http-client.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://www.postgresql.org/docs/current/transaction-iso.html)
