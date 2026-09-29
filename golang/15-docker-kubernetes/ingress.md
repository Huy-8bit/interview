# Ingress và proxy boundary

## Bài toán và ví dụ đầu tiên

Public request đi qua ingress/proxy trước khi tới Go server. Timeout, body limit và TLS ở proxy có thể làm client lỗi dù handler không ghi error nào, vì request bị chặn trước application hoặc response bị cắt sau đó.

## Đi từng bước qua một tình huống

Trace đường client→load balancer→ingress→Service→Pod. Chọn deadline layers sao cho có thời gian application trả lỗi có nghĩa trước khi outer proxy cắt nếu phù hợp use case. Streaming/WebSocket cần support và idle policy tương ứng; endpoint JSON không đại diện cho mọi route.

## Hiểu cơ chế từ kết quả quan sát

Forwarded headers chỉ tin từ proxy trusted; dùng client-supplied X-Forwarded-For làm identity/rate key vô điều kiện có thể sai. TLS termination xác định đoạn nào được mã hóa và peer identity nào được xác thực, không tự cung cấp user authorization.

## Khái niệm và mô hình làm việc

Ingress/controller xử lý HTTP routing/TLS theo platform; resource không tự hoạt động khi không có controller.

## Cơ chế và những ranh giới cần giữ

Align request/body/idle timeout, max body size và trusted forwarded headers giữa proxy và Go server. gRPC/WebSocket cần protocol support cụ thể.

## Áp dụng vào hệ thống thật

Public API terminate TLS tại trusted edge rồi internal TLS theo threat model.

## Những đường lỗi cần hiểu

Proxy timeout trả 504 trong khi backend vẫn chạy; wrong X-Forwarded-For trust bypass rate limit.

## Lần theo bằng chứng khi có sự cố

Compare edge access logs với service trace, status và request duration.

## Đánh đổi và giới hạn sử dụng

Gateway API/controller options phụ thuộc deployment; không hardcode annotation như chuẩn chung.

## Thực hành, debugging và kết luận

So access logs ở proxy với request ID server, status upstream và duration. Test oversized upload, slow body và connection drain qua toàn ingress path. Config tên annotation phụ thuộc controller/version, nên dùng docs đúng controller thay vì một YAML chung cho mọi cluster.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
