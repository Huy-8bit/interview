# Memory Runtime

Liên hệ lifetime, allocation và GC với production memory.

## Reading map

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

## Learning gate

- [ ] Nói rõ invariant và assumptions của một bài trong module.
- [ ] Vẽ lại flow hoặc chạy lab, dự đoán output trước khi xem lời giải.
- [ ] Giải thích một failure, mitigation và metric/test chứng minh fix.

[Dashboard](../README.md) · [Priority topics](../00-roadmap/priority-topics.md) · [Runnable labs](../examples/README.md)
