# Deployment và rollout capacity

## Bài toán và ví dụ đầu tiên

Rollout thay các Pods dần để phục vụ liên tục. Nếu binary mới không tương thích schema cũ hoặc readiness bật quá sớm, rolling update vẫn có thể gây lỗi dù không lúc nào replica count về zero.

## Đi từng bước qua một tình huống

Bản V1 và V2 cùng tồn tại trong cửa sổ rollout. Schema nên expand để cả hai đọc/ghi được, deploy code chuyển hành vi rồi contract sau khi V1 hết và dữ liệu đã migrate. Startup/readiness phải phản ánh điều kiện ứng dụng thực sự sẵn sàng.

## Hiểu cơ chế từ kết quả quan sát

Max surge/unavailable policy ảnh hưởng capacity và tổng pool connections trong rollout. Image rollback không đảo ngược tự động một migration destructive hoặc external effect. Config và schema version cần được xem như phần release.

## Khái niệm và mô hình làm việc

Rolling update chạy versions song song; schema/protocol phải tương thích trong cửa sổ rollout.

## Cơ chế và những ranh giới cần giữ

maxSurge và maxUnavailable điều khiển extra/reduced capacity; readiness gate traffic, strategy cần spare resources.

## Áp dụng vào hệ thống thật

Expand schema trước deploy readers/writers mới, contract sau old pods gone và migration verified.

## Những đường lỗi cần hiểu

Surge nhân DB pools vượt budget; readiness ready trước warm caches; incompatible schema.

## Lần theo bằng chứng khi có sự cố

Track available replicas, rollout progress, old/new error cohorts và DB connections.

## Đánh đổi và giới hạn sử dụng

Blue-green dễ rollback nhưng gấp đôi resources; rolling tiết kiệm hơn nhưng version skew dài.

## Thực hành, debugging và kết luận

Canary một phần traffic, so errors/P99 và business invariants, không chỉ pod Ready. Test SIGTERM/drain và rollback tương thích. Ghi release markers vào telemetry để nối symptom với thời điểm thay đổi nhưng vẫn kiểm tra giả thuyết khác.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
