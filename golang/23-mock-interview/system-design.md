# System design Mock

Câu hỏi English, answer cues Vietnamese. Tự trả lời60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## Architecture

### 1. Why define interfaces near consumers?

<details>
<summary>Answer</summary>

Contract theo nhu cầu dùng, giảm coupling tới implementation/vendor API.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 2. When is accept interfaces, return structs inappropriate?

<details>
<summary>Answer</summary>

Public polymorphic abstraction có thể nên return interface; heuristic không là luật.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 3. Is pkg a required Go directory?

<details>
<summary>Answer</summary>

Không; convention optional, internal mới có toolchain visibility semantics.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 4. How can Clean Architecture become unidiomatic Go?

<details>
<summary>Answer</summary>

Layers/interfaces/class-like abstractions rỗng che control flow/transactions.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

### 5. When is a modular monolith preferable?

<details>
<summary>Answer</summary>

Boundaries có thể giữ trong process và chưa cần independent scale/deploy.

Đọc sâu: [Go project structure không có một luật duy nhất](../11-software-architecture/go-project-structure.md).

</details>

## Timebox và scoring

Dành25–35 phút:2 phút clarify,15–20 phút questions,8 phút deep follow-up,5 phút feedback. Mỗi câu0–4:0 sai,1 definition,2 mechanism đúng,3 production failure/debugging,4 trade-off và test evidence. Không cho full score nếu chỉ kể tên tools mà không nói metric/stack/commit cần tìm.

Chọn hai câu yếu nhất, mở bài linked, viết hoặc chạy một counterexample rồi phỏng vấn lại sau48 giờ.
