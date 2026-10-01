# Lab 01 · Seq Scan vs Index Scan

## Objective

Hiểu hai cách cơ bản nhất PostgreSQL đọc một bảng — **Sequential Scan** và **Index Scan** — và
đọc được từ EXPLAIN vì sao planner chọn cách này hay cách kia.

## Problem

Màn hình CSKH tìm khách hàng theo số điện thoại. Bảng `users` có 5 triệu dòng (~2 GB heap) và
cột `phone` **chưa có index**. Mỗi lần tìm, PostgreSQL phải đọc toàn bộ bảng để trả về 1 dòng.

## Baseline Query

Q1 — Find a user by phone number (1 row out of 5,000,000)

```sql
SELECT id, username, email
FROM users
WHERE phone = '+1-236-702-0729';
```

Q2 — Count users that HAVE a phone (~85% of the table)

```sql
SELECT count(*)
FROM users
WHERE phone IS NOT NULL;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Gather  (cost=1000.00..277241.77 rows=1 width=58) (actual time=16.988..151.809 rows=1 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   Buffers: shared hit=481 read=249719
   ->  Parallel Seq Scan on users  (cost=0.00..276241.67 rows=1 width=58) (actual time=97.501..141.804 rows=0 loops=3)
         Filter: ((users.phone)::text = '+1-236-702-0729'::text)
         Rows Removed by Filter: 1666666
         Buffers: shared hit=481 read=249719
 Planning Time: 0.048 ms
 Execution Time: 151.961 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

**Seq Scan** (plan BEFORE, Q1):

```text
Gather                           <- gom kết quả của 2 worker + leader
  └── Parallel Seq Scan on users <- mỗi process đọc một phần các trang heap,
                                    kiểm tra phone = '...' trên TỪNG dòng
```

1. Leader khởi động 2 parallel worker (`Workers Launched: 2`), 3 process cùng chia nhau các
   block của heap (`loops=3`: mọi số `actual rows` là **trung bình mỗi loop**).
2. Mỗi dòng được đọc lên và so sánh với điều kiện → `Rows Removed by Filter: 1666666` mỗi loop,
   tức ~5 triệu dòng bị đọc rồi vứt đi.
3. `Gather` nhận 1 dòng duy nhất từ các worker.

**Index Scan** (plan AFTER):

```text
Index Scan using ix_lab01_users_phone on users
  Index Cond: (phone = '...')
```

1. B-tree traversal: root → internal → leaf (`bt_metap` cho thấy cây cao 3 tầng → 3 trang).
2. Leaf chứa giá trị phone đã sắp xếp + **TID** (block, offset) của dòng heap.
3. Heap fetch: đọc đúng 1 trang heap tại TID đó, kiểm tra tính khả kiến (MVCC), trả dòng.

## Bottleneck

`Parallel Seq Scan` với `Rows Removed by Filter` ≈ toàn bảng và `Buffers` ≈ toàn bộ ~250,000
trang heap. Chi phí tỉ lệ với **kích thước bảng**, không phải với số dòng kết quả.

## Optimization Strategy A

**B-tree index on users(phone)** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab01_users_phone ON users (phone);
```

## Result

AFTER Strategy A — Q1:

```text
 Index Scan using ix_lab01_users_phone on users  (cost=0.43..2.65 rows=1 width=58) (actual time=0.003..0.004 rows=1 loops=1)
   Index Cond: ((users.phone)::text = '+1-236-702-0729'::text)
   Buffers: shared hit=4
 Planning Time: 0.007 ms
 Execution Time: 0.005 ms
```

Q1: `Index Scan using ix_lab01_users_phone`, đọc vài trang, thời gian tính bằng micro giây.

## Why It Improved

Index biến bài toán "đọc 250k trang" thành "đọc ~4 trang" (3 trang B-tree + 1 trang heap).
Chi phí giờ tỉ lệ với **log(N) + số dòng khớp**. Execution Time giảm từ hàng trăm ms (hoặc vài
giây khi cache lạnh — lần chạy đầu tiên trên lab này mất 6.2 s vì phải đọc 2 GB từ đĩa) xuống
vài micro giây.

## Trade-offs

- Index ~133 MB (≈7% kích thước bảng) — xem `04_compare.sql`.
- Mọi `INSERT`, `DELETE`, và `UPDATE` cột `phone` phải cập nhật thêm cây B-tree (thêm WAL,
  thêm I/O, ảnh hưởng replica). Xem Lab 15.
- Q2 (`phone IS NOT NULL`, 85% số dòng) **không nhanh hơn**: sau khi có index, planner chuyển
  sang `Parallel Index Only Scan` toàn bộ index — vẫn là quét hết, chỉ là quét cấu trúc nhỏ hơn.
  Buffers còn tăng (3.7 triệu hit, vì Index Only Scan chạm mỗi trang index nhiều lần qua các
  tuple) mà thời gian tương đương. Index chỉ thắng khi **ít** dòng khớp.

## Optimization Strategy B

**Hash index on users(phone)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab01_users_phone_hash ON users USING hash (phone);
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Index Scan using ix_lab01_users_phone_hash on users  (cost=0.00..2.22 rows=1 width=58) (actual time=0.001..0.002 rows=1 loops=1)
   Index Cond: ((users.phone)::text = '+1-236-702-0729'::text)
   Buffers: shared hit=2
 Planning Time: 0.008 ms
 Execution Time: 0.004 ms
```

Hash index cũng cho `Index Scan` với Q1, nhỏ hơn B-tree một chút (128 MB vs 133 MB trên lab),
nhưng **chỉ hỗ trợ `=`**: câu range trong `02b_strategy_b.sql` quay về Seq Scan; nó cũng không
dùng được cho `ORDER BY`, `LIKE 'prefix%'`, không làm được `UNIQUE`, không Index Only Scan.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Find a user by phone number (1 row out of 5,000,000)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Parallel Seq Scan on public.users` | 1 | 1,666,666 | shared hit=481 read=249719 | 152.0 ms |
| Strategy A | `Index Scan using ix_lab01_users_phone on public.users` | 1 | 0 | shared hit=4 | 0.005 ms |
| Strategy B | `Index Scan using ix_lab01_users_phone_hash on public.users` | 1 | 0 | shared hit=2 | 0.004 ms |

**Q2 — Count users that HAVE a phone (~85% of the table)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 250,066 | shared hit=769 read=249431 | 178.4 ms |
| Strategy A | `Partial Aggregate, Parallel Index Only Scan using ix_lab01_users_phone on public.users` | 1 | 0 | shared hit=3726535 | 211.8 ms |
| Strategy B | `Partial Aggregate, Parallel Seq Scan on public.users` | 1 | 250,066 | shared hit=1186 read=249014 | 180.8 ms |

Kết luận: B-tree là lựa chọn mặc định — gần như cùng kích thước, hỗ trợ mọi toán tử so sánh,
sắp xếp, unique, index-only scan. Hash index chỉ đáng cân nhắc cho khóa rất dài chỉ tra bằng `=`.

## Reset

```sql
DROP INDEX IF EXISTS ix_lab01_users_phone;
DROP INDEX IF EXISTS ix_lab01_users_phone_hash;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Tên node: `Seq Scan` / `Parallel Seq Scan` vs `Index Scan using <index>`.
- `Index Cond` (điều kiện được dùng để **đi vào** index) vs `Filter` (điều kiện kiểm tra **sau**
  khi đã đọc dòng). Filter trên một Seq Scan = đọc rồi vứt.
- `Rows Removed by Filter` × `loops` = số dòng bị đọc vô ích.
- `Buffers: shared hit=… read=…`: tổng số trang 8 KB chạm tới. `read` = trang không có trong
  shared_buffers nên phải xin từ OS — có thể đến từ **OS page cache** (nhanh) hoặc đĩa (chậm).
  Lần chạy đầu và các lần sau khác nhau chính vì vậy.
- `cost=startup..total`: đơn vị tùy ý của planner (≈ chi phí đọc tuần tự 1 trang = 1.0), **không**
  phải ms. So sánh cost của các plan để hiểu lựa chọn của planner, không phải để đo thời gian.
- `rows=` ước lượng vs `actual rows=`: ở Q1 planner ước 1 dòng, thực tế 1 dòng — ước lượng tốt.

## Interview Questions

1. Khi nào PostgreSQL chọn Seq Scan dù có index phù hợp?
2. Index Scan đọc những trang nào? TID là gì?
3. `Index Cond` khác `Filter` thế nào?
4. Vì sao `shared read` không đồng nghĩa với đọc đĩa vật lý?
5. Hash index và B-tree index khác nhau ở những điểm nào? Khi nào dùng hash?
6. `cost` trong EXPLAIN có đơn vị gì? Có so sánh được giữa hai query khác nhau không?

## Key Takeaways

- Seq Scan có chi phí tỉ lệ với kích thước bảng; Index Scan tỉ lệ với log(N) + số dòng khớp.
- Index giúp khi ít dòng khớp; khi đa số dòng khớp, quét toàn bộ (bảng hay index) là không tránh được.
- Đừng đo một lần: lần đầu có thể đọc từ đĩa (giây), các lần sau từ cache (mili giây).
- Mỗi index tốn dung lượng và làm chậm thao tác ghi — chỉ tạo khi có truy vấn thực sự cần.

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
