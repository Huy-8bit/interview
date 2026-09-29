# Graceful deployment và SIGTERM budget

## Bài toán và ví dụ đầu tiên

Rolling deploy dưới tải làm vài request fail dù từng Pod có Shutdown. Có thể readiness propagation chưa xong, connection cũ vẫn tới hoặc termination budget ngắn hơn drain. Graceful deployment là phối hợp ứng dụng và nền tảng theo timeline.

## Đi từng bước qua một tình huống

Pod nhận stop, giảm nhận traffic mới theo readiness/admission, ngừng producers, drain request/worker trong budget rồi Close dependencies. Context drain phải còn sống với deadline riêng. Endpoint propagation và keep-alive cần thời gian theo môi trường, không có một Sleep cố định đúng cho mọi cluster.

## Hiểu cơ chế từ kết quả quan sát

Termination grace period là trần ngoài; application budget phải để lại thời gian cleanup và exit trước cưỡng bức. WebSocket/consumer cần lifecycle riêng ngoài Server.Shutdown. Schema phải tương thích cũ/mới vì graceful network không sửa mismatch dữ liệu.

## Khái niệm và mô hình làm việc

Rollout an toàn cần endpoint removal, drain và durable recovery cùng hoạt động.

## Cơ chế và những ranh giới cần giữ

Termination budget bao preStop, LB propagation, Server.Shutdown, worker join, flush/Close; nếu hết budget process có thể bị kill.

## Áp dụng vào hệ thống thật

Readiness false, stop new work, drain bounded, commit completed offsets, close DB cuối cùng.

## Những đường lỗi cần hiểu

Sleep preStop ăn hết grace period; WebSockets không đóng; side effect xong nhưng ack chưa gửi bị replay.

## Lần theo bằng chứng khi có sự cố

Load-test rolling deploy với in-flight calls và queue; record phase timestamps và duplicate/lost work.

## Đánh đổi và giới hạn sử dụng

Long drain giảm interruption nhưng làm rollout chậm; idempotent replay là backstop.

## Thực hành, debugging và kết luận

Test deployment thật qua ingress với request dài, consumer in-flight và SIGTERM. Theo dõi reset/5xx, duplicate retries và oldest pending jobs. Khi hết budget, lưu state đủ retry/reconcile; mục tiêu không chỉ zero crash mà cả correctness sau gián đoạn.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
