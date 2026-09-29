# Go core and runtime Mock

Câu hỏi English, answer cues Vietnamese. Tự trả lời60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## Core

### 1. Why can append mutate a caller's data?

<details>
<summary>Answer</summary>

Slice headers có thể chia backing array; append dùng lại array khi còn cap.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 2. Why can a tiny slice retain megabytes?

<details>
<summary>Answer</summary>

Pointer còn giữ whole backing allocation; clone để tách lifetime.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 3. Why is an interface containing a nil pointer non-nil?

<details>
<summary>Answer</summary>

Dynamic type vẫn tồn tại dù dynamic value là nil pointer.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 4. When can comparing interface values panic?

<details>
<summary>Answer</summary>

Dynamic value có type không comparable, ví dụ slice.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>

### 5. Why can a value call a pointer method yet fail interface assignment?

<details>
<summary>Answer</summary>

Method-call addressability convenience khác method set của T.

Đọc sâu: [Arrays, slices và ownership](../01-go-core/arrays-slices.md).

</details>


## Memory

### 6. Does returning a pointer always allocate on the heap?

<details>
<summary>Answer</summary>

Không; inlining và escape tại final caller có thể đổi placement.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 7. How can a closure affect lifetime?

<details>
<summary>Answer</summary>

Closure được giữ lâu có thể giữ captured values reachable ngoài frame.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 8. Why is allocation rate different from live heap?

<details>
<summary>Answer</summary>

Churn đo objects mới, live heap đo reachable set sau GC.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 9. Why does low STW time not imply low GC cost?

<details>
<summary>Answer</summary>

Concurrent mark/assists vẫn tiêu CPU và tăng request latency.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>

### 10. What does a write barrier protect?

<details>
<summary>Answer</summary>

GC reachability invariant khi pointers đổi, không phải user data synchronization.

Đọc sâu: [Garbage collection: live heap, pacing và memory budget](../02-memory-runtime/garbage-collector.md).

</details>


## Runtime

### 11. Which runtime claims should be version-qualified?

<details>
<summary>Answer</summary>

Scheduler queue policy, map layout, GC implementation và allocator details.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 12. How did modern Go maps change from legacy buckets?

<details>
<summary>Answer</summary>

Go 1.24 default Swiss Tables; không dùng bucket/overflow model cũ như universal.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 13. What does Green Tea change at a high level?

<details>
<summary>Answer</summary>

GC scan scheduling/locality implementation; roots, reachability và pacing vẫn cần hiểu.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 14. Why does a goroutine's initial stack not describe its total cost?

<details>
<summary>Answer</summary>

Stack grow và G giữ heap references, runtime metadata cùng tài nguyên khác.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

### 15. Can stack growth invalidate ordinary Go pointers?

<details>
<summary>Answer</summary>

Runtime/compiler bảo đảm pointers hợp lệ; unsafe/uintptr cần contract riêng.

Đọc sâu: [Runtime internals: ranh giới contract](../02-memory-runtime/runtime-internals.md).

</details>

## Timebox và scoring

Dành25–35 phút:2 phút clarify,15–20 phút questions,8 phút deep follow-up,5 phút feedback. Mỗi câu0–4:0 sai,1 definition,2 mechanism đúng,3 production failure/debugging,4 trade-off và test evidence. Không cho full score nếu chỉ kể tên tools mà không nói metric/stack/commit cần tìm.

Chọn hai câu yếu nhất, mở bài linked, viết hoặc chạy một counterexample rồi phỏng vấn lại sau48 giờ.
