# OpenTelemetry instrumentation lifecycle

## Bài toán và ví dụ đầu tiên

Team muốn một cách instrument traces/metrics không gắn business code trực tiếp vào từng backend vendor. OpenTelemetry cung cấp API/SDK và pipeline xuất telemetry, nhưng cấu hình sampling/export/lifecycle vẫn là trách nhiệm ứng dụng.

## Đi từng bước qua một tình huống

Khởi tạo providers/exporters ở application boundary, inject instrumentation nơi cần và flush/shutdown trong budget khi process dừng. Propagator nối context qua HTTP/gRPC/message. Một span được tạo nhưng không end hoặc exporter queue đầy có thể làm dữ liệu quan sát thiếu.

## Hiểu cơ chế từ kết quả quan sát

Instrumentation libraries và semantic conventions thay đổi theo version nên pin và kiểm tra migration. Telemetry pipeline cũng có backpressure; không để exporter lỗi block vô hạn request. Resource attributes như service/version/environment giúp so rollout; tránh secrets và labels không bound.

## Khái niệm và mô hình làm việc

OTel chuẩn hóa API/SDK/export để tránh binding app vào một backend; collector có lifecycle/buffer riêng.

## Cơ chế và những ranh giới cần giữ

Set service.name/version, propagate trace context, configure sampler/batch limits và bounded Shutdown flush. Avoid duplicate auto+manual spans.

## Áp dụng vào hệ thống thật

Exporter outage không được block critical requests vô hạn; bounded queue drops có metrics.

## Những đường lỗi cần hiểu

High-cardinality attributes, resource labels thay mỗi request, forgotten flush mất final spans.

## Lần theo bằng chứng khi có sự cố

Collector queue/retry/drop metrics, sampling decisions và context propagation tests.

## Đánh đổi và giới hạn sử dụng

Instrumentation có overhead; measure representative workload trước bật tất cả spans.

## Thực hành, debugging và kết luận

Dùng test/local collector xác minh spans nối đúng, metrics có units và shutdown flush hữu hạn. Đo overhead tại sampling rate dự kiến. Khi backend observability down, application cần giữ policy drop/buffer hữu hạn thay vì ăn hết memory để giữ mọi event.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://opentelemetry.io/docs/concepts/observability-primer/)

## Thực hành có điều kiện kiểm chứng

Khởi tạo provider/exporter ở startup owner; propagate context qua HTTP clients bằng instrumentation phù hợp version. Shutdown flush với fresh bounded context sau workers dừng tạo spans. Test exporter unavailable: queue memory không tăng vô hạn, request latency không phụ thuộc exporter network và drop counters tăng có alert. Không emit raw SQL parameters hoặc auth tokens trong span attributes.
