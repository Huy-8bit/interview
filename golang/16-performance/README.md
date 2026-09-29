# Đo trước khi tối ưu

Bắt đầu symptom và chọn profile phù hợp: CPU execution, memory retained/allocated hoặc thời gian chờ. Bài pprof có lệnh cùng giải thích flat/cumulative và sample types; trace bổ sung timeline. Tối ưu chỉ được xác nhận khi output đúng và mục tiêu latency/throughput/tài nguyên tốt hơn dưới workload tương đương.

## Bắt đầu và cách thực hành

Bắt đầu với [pprof](pprof.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Allocation optimization](allocations.md) | P1 |
| [Benchmark đúng workload](benchmark.md) | P1 |
| [Block profile](block-profile.md) | P1 |
| [CPU profile: execution cost](cpu-profile.md) | P1 |
| [Goroutine profiles và stack grouping](goroutine-profile.md) | P1 |
| [Heap và allocs profiles](memory-profile.md) | P1 |
| [Mutex profile](mutex-profile.md) | P1 |
| [Optimization theo bottleneck](optimization.md) | P1 |
| [Performance debugging workflow](performance-debugging.md) | P1 |
| [pprof: chọn profile từ câu hỏi production](pprof.md) | P0 |
| [Execution trace: timeline scheduling](trace.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
