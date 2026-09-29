# Bộ nhớ và runtime từ lifetime của object

Trước khi học GC internals, cần phân biệt biến local, object còn sống và tài nguyên cần Close. Module đi từ stack/heap và escape tới reachability, allocation rate, GC rồi profiles. Khi memory tăng, mô hình này giúp chọn bằng chứng cho retention hoặc churn thay vì chỉ giảm GOGC.

## Bắt đầu và cách thực hành

Bắt đầu với [stack-vs-heap](stack-vs-heap.md). Với mỗi ví dụ, viết trạng thái ban đầu, theo từng thao tác và dự đoán kết quả trước khi chạy. Khi kết quả khác dự đoán, tìm assumption sai trước khi ghi nhớ một quy tắc mới. Phần production nối cơ chế với một failure cụ thể và phép đo để kiểm chứng.

## Các bài trong module

| Bài | Ưu tiên |
|---|---|
| [Allocation rate và allocator](allocation.md) | P1 |
| [Escape analysis: đọc quyết định của compiler](escape-analysis.md) | P0 |
| [Garbage collection: live heap, pacing và memory budget](garbage-collector.md) | P0 |
| [Memory leak trong ngôn ngữ có GC](memory-leak.md) | P1 |
| [Go memory model và happens-before](memory-model.md) | P0 |
| [Memory profiling: retained versus allocated](memory-profiling.md) | P1 |
| [Object lifecycle và resource ownership](object-lifecycle.md) | P1 |
| [Runtime internals: ranh giới contract](runtime-internals.md) | P1 |
| [Stack versus heap: lifetime thay vì cú pháp](stack-vs-heap.md) | P0 |
| [Write barrier và concurrent marking](write-barrier.md) | P1 |

[Giáo trình](../README.md) · [Lộ trình học](../00-roadmap/study-first.md) · [Labs](../examples/README.md)
