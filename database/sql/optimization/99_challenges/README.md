# 99 · Challenges

15 bài tối ưu **không kèm lời giải** trong file đề. Mỗi file `challenge_NN.sql` chỉ có:
yêu cầu nghiệp vụ, query chậm, `EXPLAIN` / `EXPLAIN (ANALYZE, BUFFERS)` để bạn chạy, và một gợi ý (chỉ đọc khi bí).

Quy trình cho mỗi bài:

1. Chạy `challenge_NN.sql`, đọc plan, xác định bottleneck (node nào tốn nhiều thời gian/buffers nhất? ước lượng có sai không?).
2. Đề xuất tối ưu: index, viết lại query, statistics… Đo lại bằng `EXPLAIN (ANALYZE, BUFFERS)` — 5–10 lần.
3. Ghi lại đánh đổi: dung lượng index (`pg_relation_size`), chi phí ghi, độ tươi dữ liệu…
4. **Dọn dẹp**: drop những gì bạn tạo (đặt tên `ix_lab99_…` để `../00_environment/99_reset_all_labs.sql` dọn được), rồi chạy `../00_environment/09_verify_baseline.sql` → `BASELINE OK`.
5. So với lời giải tham khảo trong [`solutions/`](solutions/) — mỗi file lời giải tự reset ở cuối.

Lời giải không phải đáp án duy nhất: một cách khác có thể tốt hơn tùy đánh đổi bạn chấp nhận.

| # | Bài | Chủ đề | Bảng |
| --- | --- | --- | --- |
| [01](challenge_01.sql) | Find a customer by the last digits of the phone number | Index design | `users` |
| [02](challenge_02.sql) | Latest orders that used a coupon | Composite / partial index | `orders` |
| [03](challenge_03.sql) | Yearly revenue per payment method | Sargable rewrite | `payments` |
| [04](challenge_04.sql) | What must warehouse 3 restock first? | Partial index with an expression predicate | `inventory` |
| [05](challenge_05.sql) | Negative reviews of the best seller | Index for filter + sort | `reviews` |
| [06](challenge_06.sql) | Top 10 spenders of 2026 | Aggregation | `orders` |
| [07](challenge_07.sql) | Loyal customers who never write reviews | Query rewrite | `users, orders, reviews` |
| [08](challenge_08.sql) | Pink products of a category | Use the existing index | `products` |
| [09](challenge_09.sql) | Page 200 of a product's reviews | Pagination | `reviews` |
| [10](challenge_10.sql) | Daily active buyers in September | Index Only Scan + aggregation | `orders` |
| [11](challenge_11.sql) | Order lookup by order number (case-insensitive input) | Function on an indexed column | `orders, order_items, products` |
| [12](challenge_12.sql) | Customers living in Da Nang | Partial index | `users, addresses` |
| [13](challenge_13.sql) | Find a payment by its transaction id | Implicit cast | `payments` |
| [14](challenge_14.sql) | Categories with the most 5-star reviews this quarter | Join + covering partial index | `reviews, products, categories` |
| [15](challenge_15.sql) | A messy customer report | Query rewrite (everything together) | `users, orders` |

Kiểm thử tự động (chạy đề + lời giải + kiểm tra baseline cho cả 15 bài): `./scripts/test-optimization-labs.sh challenges`
