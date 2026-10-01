# Lab 06 · Column order in a composite index: equality vs range

## Objective

Hiểu vì sao **thứ tự cột** trong composite index quyết định index phục vụ được query nào, theo
quy tắc *leftmost prefix* và *equality trước, range sau*.

## Problem

Bảng điều khiển chăm sóc khách hàng đếm review 1 sao gần đây, review theo ngày, review theo số
sao. Nên tạo index `(rating, created_at)` hay `(created_at, rating)`? Ví dụ tương đương với câu
hỏi kinh điển `(user_id, status)` vs `(status, user_id)`.

## Baseline Query

Q1 — Equality on rating + range on created_at

```sql
SELECT count(*)
FROM reviews
WHERE rating = 1
  AND created_at >= '2026-09-01';
```

Q2 — Range on created_at only

```sql
SELECT count(*)
FROM reviews
WHERE created_at >= '2026-09-25';
```

Q3 — Equality on rating only

```sql
SELECT count(*)
FROM reviews
WHERE rating = 2;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=137461.82..137461.83 rows=1 width=8) (actual time=106.807..108.799 rows=1 loops=1)
   Buffers: shared hit=384 read=104776
   ->  Gather  (cost=137461.60..137461.81 rows=2 width=8) (actual time=106.735..108.792 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=384 read=104776
         ->  Partial Aggregate  (cost=136461.60..136461.61 rows=1 width=8) (actual time=100.424..100.425 rows=1 loops=3)
               Buffers: shared hit=384 read=104776
               ->  Parallel Seq Scan on reviews  (cost=0.00..136413.07 rows=19413 width=0) (actual time=89.222..100.043 rows=15475 loops=3)
                     Filter: ((reviews.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone) AND (reviews.rating = 1))
                     Rows Removed by Filter: 1651191
                     Buffers: shared hit=384 read=104776
 Planning Time: 0.038 ms
 Execution Time: 108.956 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

Hình dung B-tree như danh bạ sắp theo (họ, tên):

```text
(rating, created_at)              (created_at, rating)
1 | 2022-12-02                     2022-12-02 | 5
1 | ...                            2022-12-02 | 1
1 | 2026-09-01  <- seek here       ...
1 | 2026-09-30  <- stop here       2026-09-01 | 4   <- seek here, then read EVERY
2 | 2022-12-03                     2026-09-01 | 1      rating until the end,
...                                ...                 keep only rating = 1
```

- Q1 `rating = 1 AND created_at >= X`: với (rating, created_at) là **một đoạn liền** trong index;
  với (created_at, rating) là đoạn chứa *mọi* rating từ X, rating chỉ được kiểm tra từng entry.
- Q2 `created_at >= X` (không có rating): (created_at, rating) seek trực tiếp; (rating, created_at)
  không seek được theo created_at → planner quét toàn bộ index (đã quan sát: vẫn dùng, nhưng đọc
  ~19k trang thay vì ~450).
- Q3 `rating = 2`: ngược lại.

## Bottleneck

Không có index: cả 3 query Parallel Seq Scan ~105k trang reviews.

## Optimization Strategy A

**(rating, created_at): equality column first** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab06_reviews_rating_created ON reviews (rating, created_at);
```

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=1248.78..1248.79 rows=1 width=8) (actual time=2.720..2.720 rows=1 loops=1)
   Buffers: shared hit=189
   ->  Index Only Scan using ix_lab06_reviews_rating_created on reviews  (actual time=0.003..1.773 rows=46426 loops=1)
         Index Cond: ((reviews.rating = 1) AND (reviews.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone))
         Heap Fetches: 0
         Buffers: shared hit=189
 Planning Time: 0.011 ms
 Execution Time: 2.724 ms
```

Q1 và Q3 thành Index Only Scan rất nhỏ; Q2 dùng index nhưng phải quét gần hết (không seek được).

## Why It Improved

Mỗi index thắng đúng các query có điều kiện trên **cột đầu**:

- `(rating, created_at)`: Q1 ~190 buffers, Q3 nhanh; Q2 phải quét gần hết index (~19k buffers).
- `(created_at, rating)`: Q2 ~450 buffers; Q1 đọc cả khoảng thời gian (~1.9k buffers, chậm hơn
  ~3 lần so với index kia); Q3 quét toàn bộ index (~19k buffers).

PostgreSQL 16 **chưa có skip scan** (có từ PostgreSQL 18), nên điều kiện chỉ trên cột thứ hai
không thể seek.

## Trade-offs

- Một index không phục vụ tốt mọi query: chọn theo query quan trọng/nhiều nhất, hoặc chấp nhận hai index.
- Cột có rất ít giá trị (rating 1–5) đứng đầu vẫn tốt cho equality + range, ngược với trực giác
  "cột selective nhất đứng đầu": điều quan trọng là **kiểu điều kiện** (=, range, ORDER BY).

## Optimization Strategy B

**(created_at, rating): range column first** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab06_reviews_created_rating ON reviews (created_at, rating);
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=7708.69..7708.70 rows=1 width=8) (actual time=7.580..7.580 rows=1 loops=1)
   Buffers: shared hit=1902
   ->  Index Only Scan using ix_lab06_reviews_created_rating on reviews  (actual time=0.004..6.642 rows=46426 loops=1)
         Index Cond: ((reviews.created_at >= '2026-09-01 00:00:00+00'::timestamp with time zone) AND (reviews.rating = 1))
         Heap Fetches: 0
         Buffers: shared hit=1902
 Planning Time: 0.017 ms
 Execution Time: 7.585 ms
```

Q2 thành Index Only Scan nhỏ; Q1 phải đọc mọi rating trong khoảng thời gian; Q3 quét toàn bộ index.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Equality on rating + range on created_at**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.reviews` | 1 | 1,651,191 | shared hit=384 read=104776 | 109.0 ms |
| Strategy A | `Index Only Scan using ix_lab06_reviews_rating_created on public.reviews` | 1 | 0 | shared hit=189 | 2.724 ms |
| Strategy B | `Index Only Scan using ix_lab06_reviews_created_rating on public.reviews` | 1 | 0 | shared hit=1902 | 7.585 ms |

**Q2 — Range on created_at only**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.reviews` | 1 | 1,627,536 | shared hit=672 read=104488 | 109.1 ms |
| Strategy A | `Index Only Scan using ix_lab06_reviews_rating_created on public.reviews` | 1 | 0 | shared hit=19161 | 42.9 ms |
| Strategy B | `Index Only Scan using ix_lab06_reviews_created_rating on public.reviews` | 1 | 0 | shared hit=454 | 6.265 ms |

**Q3 — Equality on rating only**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.reviews` | 1 | 1,561,281 | shared hit=960 read=104200 | 92.5 ms |
| Strategy A | `Partial Aggregate, Parallel Index Only Scan using ix_lab06_reviews_rating_created on public.reviews` | 1 | 0 | shared hit=1253 | 7.880 ms |
| Strategy B | `Partial Aggregate, Parallel Index Only Scan using ix_lab06_reviews_created_rating on public.reviews` | 1 | 0 | shared hit=19198 | 58.8 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab06_reviews_rating_created;
DROP INDEX IF EXISTS ix_lab06_reviews_created_rating;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Trong `Index Cond`, điều kiện trên cột đầu là *seek*, điều kiện trên cột sau có thể chỉ là
  *lọc trong khoảng đã quét* — EXPLAIN không phân biệt, **Buffers** thì có.
- So `Buffers` của cùng một query với hai index: đó là thước đo số trang index phải đọc.

## Interview Questions

1. Quy tắc leftmost prefix là gì?
2. Với `WHERE a = ? AND b > ?`, index (a, b) hay (b, a) tốt hơn? Vì sao?
3. Index (a, b) có dùng được cho `WHERE b = ?` không? PostgreSQL 18 thay đổi gì?
4. Có nên luôn đặt cột có selectivity cao nhất lên đầu?
5. Làm sao chứng minh index nào tốt hơn cho một query bằng EXPLAIN?

## Key Takeaways

- Equality trước, range/ORDER BY sau.
- Index chỉ seek được trên prefix bên trái của danh sách cột.
- Cùng một Index Cond có thể tốn 10× số trang tùy thứ tự cột: so Buffers, không chỉ tên node.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`02b_strategy_b.sql`](02b_strategy_b.sql) | Strategy B |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
