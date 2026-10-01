# Lab 16 · Nested Loop: small outer side + indexed inner lookups

## Objective

Hiểu **Nested Loop**: cách nó chạy, vì sao nó tối ưu khi phía ngoài nhỏ và phía trong có index, và khi nào planner rời bỏ nó.

## Problem

Trang 'lịch sử mua hàng' của một khách: đơn hàng → các dòng hàng → tên sản phẩm. Ba bảng lớn (5M, 10M, 5M dòng) nhưng chỉ cần ~30 dòng.

## Baseline Query

Q1 — Order history of one customer: orders -> order lines -> products

```sql
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 2215979
ORDER BY o.created_at;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Sort  (cost=25.76..25.77 rows=6 width=67) (actual time=0.056..0.056 rows=28 loops=1)
   Sort Key: o.created_at
   Sort Method: quicksort  Memory: 27kB
   Buffers: shared hit=195
   ->  Nested Loop  (cost=1.30..25.68 rows=6 width=67) (actual time=0.006..0.053 rows=28 loops=1)
         Inner Unique: true
         Buffers: shared hit=195
         ->  Nested Loop  (cost=0.87..12.80 rows=6 width=46) (actual time=0.004..0.024 rows=28 loops=1)
               Buffers: shared hit=83
               ->  Index Scan using idx_orders_user_id on orders o  (actual time=0.002..0.004 rows=16 loops=1)
                     Index Cond: (o.user_id = 2215979)
                     Buffers: shared hit=19
               ->  Index Scan using idx_order_items_order_id on order_items i  (actual time=0.001..0.001 rows=2 loops=16)
                     Index Cond: (i.order_id = o.id)
                     Buffers: shared hit=64
         ->  Index Scan using pk_products on products p  (cost=0.43..2.15 rows=1 width=37) (actual time=0.001..0.001 rows=1 loops=28)
               Index Cond: (p.id = i.product_id)
               Buffers: shared hit=112
   Buffers: shared hit=32
 Planning Time: 0.095 ms
 Execution Time: 0.062 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Sort (o.created_at)
  └── Nested Loop                                       (2) với mỗi dòng order_items → tra products
        ├── Nested Loop                                 (1) với mỗi order → tra order_items
        │     ├── Index Scan using idx_orders_user_id    outer: 16 đơn của user
        │     └── Index Scan using idx_order_items_order_id   inner: loops=16, ~2 dòng/loop
        └── Index Scan using pk_products                inner: loops=28, 1 dòng/loop
```

```text
outer row 1 → lookup inner (index) → emit matches
outer row 2 → lookup inner (index) → emit matches
...
```
Thứ tự thực thi: node ngoài cùng bên trái (outer) chạy một lần; node bên phải (inner) chạy lại
**mỗi dòng outer** — `loops=16`, `loops=28`. Số `actual rows` của inner là **trung bình mỗi loop**.

## Bottleneck

Không có: baseline đã tối ưu (micro giây). Lab này dùng các thí nghiệm để hiểu *vì sao* planner chọn Nested Loop.

## Optimization Strategy A

**(experiment) SET enable_nestloop = off: what would the alternative cost?** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Gather Merge  (cost=438173.74..438174.21 rows=4 width=67) (actual time=478.850..481.129 rows=28 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   Buffers: shared hit=569 read=355485
   ->  Sort  (cost=437173.72..437173.72 rows=2 width=67) (actual time=465.667..465.669 rows=9 loops=3)
         Sort Key: o.created_at
         Sort Method: quicksort  Memory: 26kB
         Buffers: shared hit=569 read=355485
         ->  Parallel Hash Join  (cost=146972.87..437173.71 rows=2 width=67) (actual time=281.160..465.604 rows=9 loops=3)
               Hash Cond: (p.id = i.product_id)
               Buffers: shared hit=553 read=355485
               ->  Parallel Seq Scan on products p  (actual time=0.047..142.432 rows=1666667 loops=3)
                     Buffers: shared hit=220 read=261335
               ->  Parallel Hash  (cost=146972.84..146972.84 rows=2 width=46) (actual time=262.982..262.983 rows=9 loops=3)
                     Buckets: 1024  Batches: 1  Memory Usage: 104kB
                     Buffers: shared hit=273 read=94150
                     ->  Hash Join  (cost=4.52..146972.84 rows=2 width=46) (actual time=70.054..262.886 rows=9 loops=3)
                           Inner Unique: true
                           Hash Cond: (i.order_id = o.id)
                           Buffers: shared hit=273 read=94150
                           ->  Parallel Seq Scan on order_items i  (actual time=0.049..138.699 rows=3333715 loops=3)
                                 Buffers: shared hit=208 read=94150
                           ->  Hash  (cost=4.48..4.48 rows=3 width=36) (actual time=9.146..9.146 rows=16 loops=3)
                                 Buckets: 1024  Batches: 1  Memory Usage: 10kB
                                 Buffers: shared hit=65
                                 ->  Index Scan using idx_orders_user_id on orders o  (actual time=9.103..9.135 rows=16 loops=3)
                                       Index Cond: (o.user_id = 2215979)
                                       Buffers: shared hit=65
   Buffers: shared hit=32
 Planning Time: 0.233 ms
 Execution Time: 481.526 ms
```

Không có Nested Loop: `Parallel Hash Join` với Seq Scan trên order_items và products — hàng trăm ms thay vì micro giây.

## Why It Improved

Strategy A tắt Nested Loop: planner buộc phải Hash Join — tức đọc **toàn bộ** `order_items` (10M) và
`products` (5M) bằng Seq Scan để lấy 28 dòng: chậm hơn hàng nghìn lần. Đây là lý do Nested Loop
được chọn: chi phí = (dòng outer) × (một lần tra index), rất nhỏ khi outer nhỏ.

## Trade-offs

- Nested Loop tuyến tính theo số dòng outer: nếu planner **ước lượng sai** outer (nghĩ 10 dòng,
  thực tế 1 triệu), Nested Loop trở thành thảm họa (xem Lab 33, 35).
- Inner không có index → mỗi loop là một Seq Scan → planner gần như không bao giờ chọn (trừ
  bảng rất nhỏ hoặc có Materialize/Memoize).

## Optimization Strategy B

**(experiment) Grow the outer side: when does the planner leave the Nested Loop?** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Gather Merge  (cost=13824.22..14152.43 rows=2854 width=67) (actual time=14.731..17.557 rows=4776 loops=1)
   Workers Planned: 1
   Workers Launched: 1
   Buffers: shared hit=31356
   ->  Sort  (cost=12824.21..12831.34 rows=2854 width=67) (actual time=12.695..12.774 rows=2388 loops=2)
         Sort Key: o.created_at
         Sort Method: quicksort  Memory: 355kB
         Buffers: shared hit=31356
         ->  Nested Loop  (cost=31.67..12660.41 rows=2854 width=67) (actual time=0.855..12.228 rows=2388 loops=2)
               Inner Unique: true
               Buffers: shared hit=31348
               ->  Nested Loop  (cost=31.23..6534.99 rows=2854 width=46) (actual time=0.827..6.138 rows=2388 loops=2)
                     Buffers: shared hit=12243
                     ->  Parallel Bitmap Heap Scan on orders o  (actual time=0.797..2.388 rows=1222 loops=2)
                           Recheck Cond: ((o.user_id >= 2000000) AND (o.user_id <= 2002500))
                           Heap Blocks: exact=1322
                           Buffers: shared hit=2439
                           ->  Bitmap Index Scan on idx_orders_user_id  (actual time=1.074..1.074 rows=2444 loops=1)
                                 Index Cond: ((o.user_id >= 2000000) AND (o.user_id <= 2002500))
                                 Buffers: shared hit=8
                     ->  Index Scan using idx_order_items_order_id on order_items i  (actual time=0.003..0.003 rows=2 loops=2444)
                           Index Cond: (i.order_id = o.id)
                           Buffers: shared hit=9804
               ->  Index Scan using pk_products on products p  (actual time=0.002..0.002 rows=1 loops=4776)
                     Index Cond: (p.id = i.product_id)
                     Buffers: shared hit=19105
   Buffers: shared hit=32
 Planning Time: 0.221 ms
 Execution Time: 17.755 ms
```

Phía outer lớn dần (cùng query): ~1,000 khách vẫn là Nested Loop (vài chục ms). ~100,000 khách: planner
chuyển `orders ⋈ order_items` sang **Parallel Hash Join**, còn lookup products giữ Nested Loop nhưng có
thêm **Memoize** (cache kết quả lookup theo `product_id`: Hits/Misses) — và Sort tràn đĩa.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Order history of one customer: orders -> order lines -> products**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Nested Loop, Index Scan using idx_orders_user_id on public.orders o, Index Scan using idx_order_items_order_id on public` | 28 | 0 | shared hit=195 | 0.062 ms |

**Strategy A — (experiment) SET enable_nestloop = off: what would the alternative cost?**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Same query with nested loops disabled | `Sort, Parallel Hash Join, Parallel Seq Scan on public.products p, Hash Join, Parallel Seq Scan on public.order_items i, ` | 28 | 0 | shared hit=569 read=355485 | 481.5 ms |

**Strategy B — (experiment) Grow the outer side: when does the planner leave the Nested Loop?**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| ~1,000 customers (user_id range of 2,500) | `Sort, Nested Loop, Parallel Bitmap Heap Scan on public.orders o, Bitmap Index Scan on idx_orders_user_id, Index Scan usi` | 4776 | 0 | shared hit=31356 | 17.8 ms |
| ~100,000 customers (user_id range of 250,000) | `Sort, Nested Loop, Parallel Hash Join, Parallel Seq Scan on public.order_items i, Parallel Bitmap Heap Scan on public.or` | 499204 | 0 | shared hit=645885 read=399717, temp read=5158 written=5164 | 2,737.8 ms |

## Reset

```sql
RESET enable_nestloop;
-- (nothing to undo: no DDL, no settings)
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `loops=` trên node inner; tổng dòng = rows × loops; tổng thời gian ≈ time × loops.
- Index Scan bên trong Nested Loop dùng `Index Cond: (id = i.product_id)` — tham số từ outer.
- `Memoize` (PG14+): Hits / Misses / Evictions.

## Interview Questions

1. Nested Loop hoạt động thế nào? Chi phí của nó tỉ lệ với gì?
2. Vì sao Nested Loop cần index ở phía inner?
3. Memoize là gì và khi nào planner thêm nó?
4. Nested Loop có hỗ trợ mọi loại điều kiện join (>, <, LIKE)? Hash/Merge Join thì sao?
5. Điều gì xảy ra khi planner ước lượng outer quá thấp?

## Key Takeaways

- Nested Loop + index lookup là join tốt nhất cho tập kết quả nhỏ.
- Đọc loops= để biết node inner chạy bao nhiêu lần.
- Nested Loop là loại join duy nhất hỗ trợ điều kiện không phải bằng (theta join) mà không cần sort/hash.
- Rủi ro lớn nhất của Nested Loop là ước lượng sai số dòng outer.

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
