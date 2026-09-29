# Python Cheatsheet

## Object / Memory
- Name → reference → object; assignment không copy. `is` identity, `==` equality.
- CPython: refcount + cyclic GC; `del` bỏ reference. Resource dùng `with`, không chờ GC.
- Mutable default argument tồn tại qua nhiều call. Copy shallow chia sẻ nested object.

## GIL / Concurrency
- GIL: một thread chạy Python bytecode/interpreter; I/O và native extension có thể nhả GIL.
- I/O-bound: AsyncIO hoặc thread. CPU-bound Python: process/native/worker queue.
- Async là cooperative: blocking call chặn event loop. Có timeout, cancellation, semaphore.

## Senior Phrases
- “I would first classify CPU vs I/O and measure event-loop lag.”
- “Thread safety is not guaranteed by the GIL; compound operations can interleave.”
- “I use context managers for deterministic cleanup and bound all concurrency.”
