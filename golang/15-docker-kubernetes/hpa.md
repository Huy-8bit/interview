# HPA và scaling limits

## Bài toán và ví dụ đầu tiên

Traffic tăng, HPA thêm replica dựa metric. Nhưng scale-up có độ trễ khởi động và mỗi replica mới thêm DB connections; autoscaling không đảm bảo một downstream cố định chịu được tổng tải tăng.

## Đi từng bước qua một tình huống

CPU metric phù hợp workload CPU-bound nhưng consumer chờ DB có CPU thấp dù lag tăng. Queue age/lag hoặc request metrics có thể phản ánh nhu cầu hơn theo policy, nhưng cần giới hạn replicas và kiểm tra dependency budget. Scaling không vượt qua bottleneck hot partition tự động.

## Hiểu cơ chế từ kết quả quan sát

Control loop có delay, stabilization và sampling nên không phản ứng tức thì mọi burst. Scale-down phải drain workers và giữ checkpoint đúng. Nếu mỗi replica có pool 50 thì max replicas 100 cho nhu cầu tới 5000 connections; ngân sách fleet phải tính ở mức đó.

## Khái niệm và mô hình làm việc

HPA đổi replica count theo metrics/control loop; phản ứng có delay và không tạo downstream capacity.

## Cơ chế và những ranh giới cần giữ

CPU utilization target phụ thuộc requests; custom queue age/lag có thể hợp workers hơn CPU. Bound min/max và stabilization để giảm flapping.

## Áp dụng vào hệ thống thật

Scale API từ measured per-pod throughput, giữ aggregate DB/Redis/client budgets trong giới hạn.

## Những đường lỗi cần hiểu

Low CPU nhưng DB-wait saturation không trigger CPU HPA; tăng consumers quá partitions vô ích.

## Lần theo bằng chứng khi có sự cố

Desired/current replicas, metric freshness, pending pods và bottleneck downstream.

## Đánh đổi và giới hạn sử dụng

Autoscaling giảm manual sizing nhưng không hấp thụ instant burst; cần admission/queue/headroom.

## Thực hành, debugging và kết luận

Test ramp và burst dài/ngắn, đo time-to-capacity cùng rejected work. Observe pending Pods, startup và downstream saturation. Dùng queue/admission hữu hạn để chịu khoảng trước scale, không lưu work vô hạn vì tin autoscaler sẽ đuổi kịp.


## Đọc tiếp

- [Graceful shutdown và dependency order](../06-http-backend/graceful-shutdown.md)
- [GOMAXPROCS và container CPU](../03-goroutines-scheduler/gomaxprocs.md)
- [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://kubernetes.io/docs/concepts/)
