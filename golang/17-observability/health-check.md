# Health checks: liveness, readiness, startup

## Bài toán và ví dụ đầu tiên

Process trả /health200 nhưng mọi API cần DB đều lỗi; ngược lại DB tạm chậm làm liveness fail khiến restart liên tục. Health cần phân biệt process sống, có thể nhận traffic và dependency nào đang ảnh hưởng capability.

## Đi từng bước qua một tình huống

Liveness kiểm tra trạng thái mà restart có thể giúp, readiness thể hiện instance nên được route việc mới, startup cho thời gian initialize. Một optional recommendation outage không nhất thiết làm core API unready. Probe phải rẻ, bounded và không tạo tải đáng kể vào dependency.

## Hiểu cơ chế từ kết quả quan sát

Health là tín hiệu hiện tại với propagation delay, không đảm bảo request tiếp theo thành công. Deep dependency check có thể gây cascade khi mọi replica đồng thời bị loại. Cần biểu diễn degraded capabilities và SLO bằng metrics khác thay vì nhồi mọi thứ vào một bool.

## Khái niệm và mô hình làm việc

Liveness hỏi process có tiến triển không; readiness hỏi có nên nhận traffic; startup bảo vệ slow initialization.

## Cơ chế và những ranh giới cần giữ

Readiness bounded/lightweight; avoid making liveness depend on shared DB. Health endpoint không trả secrets/config.

## Áp dụng vào hệ thống thật

Readiness false khi drain; startup probe cho migration/init policy có deadline.

## Những đường lỗi cần hiểu

DB outage làm mọi pods fail liveness rồi restart storm; probe timeout quá ngắn lúc CPU throttle.

## Lần theo bằng chứng khi có sự cố

Correlate probe failures/restarts và real request SLO; xem rollout timing.

## Đánh đổi và giới hạn sử dụng

Readiness toàn bộ dependency fail có thể remove mọi pod; decide degraded service policy.

## Thực hành, debugging và kết luận

Test dependency down, startup dài và shutdown readiness change. Xem restart count và traffic routing để xác định probe có giúp recovery hay làm nặng thêm. Document policy cho từng check để người vận hành hiểu 200 hoặc failure thực sự có nghĩa gì.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://opentelemetry.io/docs/concepts/observability-primer/)
