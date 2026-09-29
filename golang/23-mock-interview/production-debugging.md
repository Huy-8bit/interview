# Production debugging Mock

Đây là phụ lục luyện tập sau giáo trình. Đọc bài lý thuyết liên quan trước, dùng đáp án để đối chiếu reasoning rồi quay lại ví dụ nếu chưa giải thích được cơ chế. Câu hỏi ở đây được giữ riêng, không là cấu trúc của các bài học.

Câu hỏi English, answer cues Vietnamese. Tự trả lời 60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## Performance

### 1. Which profile answers where CPU time is spent?

<details>
<summary>Answer</summary>

CPU sampled stacks; inspect flat/cum/callers và quota metrics.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 2. Which profile distinguishes retained memory from churn?

<details>
<summary>Answer</summary>

Heap inuse_space so với alloc_space/alloc_objects.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 3. Why can summed contention exceed wall time?

<details>
<summary>Answer</summary>

Nhiều waiters cùng chờ được cộng vào cumulative contention.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 4. What does a goroutine snapshot fail to tell you alone?

<details>
<summary>Answer</summary>

Duration/progress/lifetime validity; cần repeated snapshots/timeline.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>

### 5. When is execution trace preferable to aggregate profiles?

<details>
<summary>Answer</summary>

Cần scheduling delay, overlap và GC/network timeline.

Đọc sâu: [pprof: chọn profile từ câu hỏi production](../16-performance/pprof.md).

</details>


## Production

### 6. How would you investigate 20000 goroutines?

<details>
<summary>Answer</summary>

Trend sau drain, stack groups, owner/cancel paths và dependency waits.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 7. Why can stopping a ticker leave a goroutine blocked?

<details>
<summary>Answer</summary>

Stop không close C; range loop cần separate cancellation.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 8. Why can Redis failure overload PostgreSQL?

<details>
<summary>Answer</summary>

Cache misses tăng đột biến; bounded fallback/admission cần có sẵn.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 9. Why can HPA worsen pool exhaustion?

<details>
<summary>Answer</summary>

New replicas nhân total connections/demand lên cùng bottleneck.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

### 10. What follows DB success before Kafka offset commit?

<details>
<summary>Answer</summary>

Redelivery; dedup+effect transaction bảo vệ replay.

Đọc sâu: [20,000 goroutines trong production](../20-production-scenarios/goroutine-leak.md).

</details>

## Timebox và scoring

Dành25–35 phút:2 phút clarify,15–20 phút questions,8 phút deep follow-up,5 phút feedback. Mỗi câu0–4:0 sai,1 definition,2 mechanism đúng,3 production failure/debugging,4 trade-off và test evidence. Không cho full score nếu chỉ kể tên tools mà không nói metric/stack/commit cần tìm.

Chọn hai câu yếu nhất, mở bài linked, viết hoặc chạy một counterexample rồi phỏng vấn lại sau48 giờ.
