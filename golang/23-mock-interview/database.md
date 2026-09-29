# Database Mock

Đây là phụ lục luyện tập sau giáo trình. Đọc bài lý thuyết liên quan trước, dùng đáp án để đối chiếu reasoning rồi quay lại ví dụ nếu chưa giải thích được cơ chế. Câu hỏi ở đây được giữ riêng, không là cấu trúc của các bài học.

Câu hỏi English, answer cues Vietnamese. Tự trả lời 60–90 giây rồi mở đáp án; câu trả lời senior cần thêm trade-off và failure evidence.

## Database

### 1. What does sql.DB represent?

<details>
<summary>Answer</summary>

Long-lived concurrent-safe pool handle, không một connection.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 2. What happens with 500 requests and 20 open connections?

<details>
<summary>Answer</summary>

Chỉ tối đa 20 giữ slots, excess acquire waits/deadlines theo workload.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 3. How should WaitDuration be interpreted?

<details>
<summary>Answer</summary>

Cumulative counter; delta theo window và delta WaitCount cho waits observed.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 4. Why must Rows.Err be checked after iteration?

<details>
<summary>Answer</summary>

Next false có thể vì error chứ không chỉ EOF.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

### 5. Why can using db inside a transaction deadlock?

<details>
<summary>Answer</summary>

Tx giữ connection; db call cần connection khác khi pool đã đầy.

Đọc sâu: [database/sql: pool handle, rows và transaction ownership](../08-database/database-sql.md).

</details>

## Timebox và scoring

Dành25–35 phút:2 phút clarify,15–20 phút questions,8 phút deep follow-up,5 phút feedback. Mỗi câu0–4:0 sai,1 definition,2 mechanism đúng,3 production failure/debugging,4 trade-off và test evidence. Không cho full score nếu chỉ kể tên tools mà không nói metric/stack/commit cần tìm.

Chọn hai câu yếu nhất, mở bài linked, viết hoặc chạy một counterexample rồi phỏng vấn lại sau48 giờ.
