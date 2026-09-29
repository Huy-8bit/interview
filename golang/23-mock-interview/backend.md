# Backend and HTTP Mock

Đây là phụ lục luyện tập sau giáo trình. Đọc bài lý thuyết liên quan trước, dùng đáp án để đối chiếu reasoning rồi quay lại ví dụ nếu chưa giải thích được cơ chế. Câu hỏi ở đây được giữ riêng, không là cấu trúc của các bài học.

Câu hỏi English, answer cues Vietnamese. Tự trả lời 60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## HTTP

### 1. Why should Transport be reused?

<details>
<summary>Answer</summary>

Nó giữ connection pool; new Transport tạo TCP/TLS/FD churn.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 2. Does a new http.Client always create a new pool?

<details>
<summary>Answer</summary>

Không; nil Transport dùng shared DefaultTransport.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 3. Why close response bodies after non-2xx responses?

<details>
<summary>Answer</summary>

Do success trao body ownership bất kể status; release resource vẫn bắt buộc.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 4. Why may closing a body not ensure HTTP/1 reuse?

<details>
<summary>Answer</summary>

Chưa đọc EOF có thể khiến connection không reuse được.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

### 5. Why not drain every body without limits?

<details>
<summary>Answer</summary>

Untrusted/infinite body có thể giữ memory/time; bound read rồi close.

Đọc sâu: [HTTP client reuse và response ownership](../06-http-backend/http-client.md).

</details>

## Timebox và scoring

Dành25–35 phút:2 phút clarify,15–20 phút questions,8 phút deep follow-up,5 phút feedback. Mỗi câu0–4:0 sai,1 definition,2 mechanism đúng,3 production failure/debugging,4 trade-off và test evidence. Không cho full score nếu chỉ kể tên tools mà không nói metric/stack/commit cần tìm.

Chọn hai câu yếu nhất, mở bài linked, viết hoặc chạy một counterexample rồi phỏng vấn lại sau48 giờ.
