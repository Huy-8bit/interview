# Metrics: counters, gauges và histograms

## Bài toán và ví dụ đầu tiên

Dashboard CPU bình thường nhưng người dùng lỗi. Metrics là số liệu tổng hợp theo thời gian; phải chọn từ hành vi user thấy và tài nguyên giới hạn, không chỉ những gì dễ đếm.

## Đi từng bước qua một tình huống

Đo request rate, error rate và latency distribution theo route/status class. Histogram giữ phân bố phục vụ percentile aggregation phù hợp; average không cho biết P99. Counter tăng tích lũy cần rate/delta theo cửa sổ, gauge biểu diễn mức hiện tại như in-flight.

## Hiểu cơ chế từ kết quả quan sát

Mỗi tổ hợp labels tạo một time series. User ID/request ID/path chứa UUID gây cardinality tăng không giới hạn, tiêu memory/storage. Dùng route template và nhóm hữu hạn; IDs chi tiết đặt ở logs/traces có policy. Percentile của từng instance không được trung bình hóa để ra percentile fleet.

## Khái niệm và mô hình làm việc

Metric tập hợp numeric signals có cardinality bound để quan sát rates và distributions.

## Cơ chế và những ranh giới cần giữ

Counter dùng rate/increase, gauge cho current state, histogram cho latency buckets; label route template không user/request ID.

## Áp dụng vào hệ thống thật

RED: rate/errors/duration; USE: utilization/saturation/errors cho pools/CPU.

## Những đường lỗi cần hiểu

Average latency che tail; counter reset bị coi traffic giảm; label explosion OOM metrics backend.

## Lần theo bằng chứng khi có sự cố

Inspect series count, bucket coverage và scrape lag; compare offered versus completed requests.

## Đánh đổi và giới hạn sử dụng

Không aggregate percentiles bằng average P99; merge histogram distributions đúng cách.

## Thực hành, debugging và kết luận

Validate metric lúc lỗi/retry/reject, không chỉ success. Offered, accepted và completed cần phân biệt để không báo hệ thống khỏe vì đang reject nhanh. Dashboard nối SLO với queue age, pool wait và resource saturation.


## Đọc tiếp

- [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md)
- [service-outage](../20-production-scenarios/service-outage.md)

## Nguồn đối chiếu

- [Tài liệu chính thức](https://opentelemetry.io/docs/concepts/observability-primer/)

## Thực hành có điều kiện kiểm chứng

Giả sử một pod có100 requests và P99=1s, pod khác có10k requests P99=50ms: average525ms không là fleet P99. Aggregate histogram buckets/counts theo time window rồi tính quantile/fraction. Include timeout/reject events theo eligible definition; nếu chỉ observe successful requests, latency dashboard có thể xanh ngay khi phần lớn users fail.

## Runtime metrics example

Chương trình độc lập dùng public `runtime/metrics`; xem descriptions từ `metrics.All()` trên toolchain deploy để biết loại và units. Không coi mọi metric là gauge: heap alloc bytes và GC cycles là cumulative counters, goroutine count/live heap là snapshots.

```go
package main
import (
    "fmt"
    "runtime/metrics"
)
func main() {
    names := []string{
        "/sched/goroutines:goroutines",
        "/gc/heap/allocs:bytes",
        "/gc/heap/live:bytes",
        "/gc/cycles/total:gc-cycles",
    }
    samples := make([]metrics.Sample, len(names))
    for i, name := range names { samples[i].Name = name }
    metrics.Read(samples)
    for _, sample := range samples {
        if sample.Value.Kind() != metrics.KindUint64 {
            fmt.Printf("%s: unavailable or different kind\n", sample.Name)
            continue
        }
        fmt.Printf("%s=%d\n", sample.Name, sample.Value.Uint64())
    }
}
```

### Giải thích code và kết quả

Names chọn bốn runtime metrics theo units trong tên. Mỗi Sample gán Name trước metrics.Read; vòng sau kiểm tra KindUint64 trước đọc để không giả định một metric luôn có kind đó ở mọi version. Goroutines/live heap là mức hiện tại theo semantics metric, allocs/cycles là totals cần delta khi muốn rate. Chương trình in snapshot đơn, không phải exporter Prometheus hay phép đo RSS toàn process.

Lấy deltas alloc bytes/cycles giữa hai thời điểm và chia elapsed seconds, xử lý process restart/reset. `/sched/latencies:seconds` là histogram, không được đọc bằng Uint64; đọc Float64Histogram và interpret bucket counts theo contract. Scheduler latency khác HTTP latency: cần correlate với request traces/queue metrics để suy nguyên nhân. [Runtime metric descriptions](https://pkg.go.dev/runtime/metrics).
