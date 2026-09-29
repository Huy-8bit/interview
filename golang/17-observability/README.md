# Từ tín hiệu tới lời giải thích sự cố

Metrics cho trend/distribution, traces nối các bước của request, logs ghi sự kiện có context. Module bắt đầu user-visible outcomes rồi chọn labels/spans và SLO, tránh thu rất nhiều dữ liệu mà vẫn không biết operation đã commit chưa. Telemetry giúp điều tra nhưng không thay durable state nghiệp vụ.

## Bắt đầu và cách thực hành

Bắt đầu với [metrics](metrics.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Health checks: liveness, readiness, startup](health-check.md) | P1 |
| [Incident debugging với evidence](incident-debugging.md) | P1 |
| [Structured logging có context](logging.md) | P1 |
| [Metrics: counters, gauges và histograms](metrics.md) | P1 |
| [OpenTelemetry instrumentation lifecycle](opentelemetry.md) | P1 |
| [Prometheus metrics cho Go](prometheus.md) | P1 |
| [SLI, SLO, SLA và error budget](sli-slo-sla.md) | P1 |
| [Tracing và critical path](tracing.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
