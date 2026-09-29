# Concurrency Mock

Đây là phụ lục luyện tập sau giáo trình. Đọc bài lý thuyết liên quan trước, dùng đáp án để đối chiếu reasoning rồi quay lại ví dụ nếu chưa giải thích được cơ chế. Câu hỏi ở đây được giữ riêng, không là cấu trúc của các bài học.

Câu hỏi English, answer cues Vietnamese. Tự trả lời 60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## Scheduler

### 1. How do G, M and P divide responsibilities?

<details>
<summary>Answer</summary>

G là execution context, M thread, P resource để chạy Go code.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 2. Does GOMAXPROCS cap OS threads?

<details>
<summary>Answer</summary>

Không; M có thể blocked syscall/cgo hoặc locked thread ngoài executing P.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 3. What happens to P during a blocking syscall?

<details>
<summary>Answer</summary>

Có thể release/retake để M khác chạy Go, không buộc chờ cùng M.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 4. How does network waiting differ from blocking disk I/O?

<details>
<summary>Answer</summary>

Runtime-managed nonblocking sockets park G qua netpoll; disk/cgo có thể giữ M.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>

### 5. What happens when a syscall returns without an available P?

<details>
<summary>Answer</summary>

G có thể enqueue và M park thay chạy Go không có P.

Đọc sâu: [Go scheduler: G, M, P và các đường blocking](../03-goroutines-scheduler/scheduler-gmp.md).

</details>


## Concurrency

### 6. Does a buffered send confirm processing completed?

<details>
<summary>Answer</summary>

Không, chỉ handoff/enqueue; completion cần ack hoặc result protocol.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 7. What happens to receivers after a channel is closed?

<details>
<summary>Answer</summary>

Drain buffered values rồi zero,false; closed receive luôn ready.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 8. Why can select ignore cancellation for one iteration?

<details>
<summary>Answer</summary>

Jobs và Done cùng ready thì chọn pseudo-random, không priority.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 9. Who should close a channel shared by many producers?

<details>
<summary>Answer</summary>

Coordinator sau khi biết mọi producers đã dừng gửi.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

### 10. How can channel-based code still have a data race?

<details>
<summary>Answer</summary>

Gửi pointer/slice không deep-copy; sender/receiver cùng mutate object.

Đọc sâu: [Channel internals và synchronization](../04-concurrency/channels.md).

</details>

## Timebox và scoring

Dành25–35 phút:2 phút clarify,15–20 phút questions,8 phút deep follow-up,5 phút feedback. Mỗi câu0–4:0 sai,1 definition,2 mechanism đúng,3 production failure/debugging,4 trade-off và test evidence. Không cho full score nếu chỉ kể tên tools mà không nói metric/stack/commit cần tìm.

Chọn hai câu yếu nhất, mở bài linked, viết hoặc chạy một counterexample rồi phỏng vấn lại sau48 giờ.
