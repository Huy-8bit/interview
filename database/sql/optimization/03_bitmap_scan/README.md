# Lab 03 · Bitmap Index Scan + Bitmap Heap Scan, BitmapAnd

## Objective

Hiểu **Bitmap Index Scan → Bitmap Heap Scan**: khi nào PostgreSQL chọn nó thay vì Index Scan,
`BitmapAnd` kết hợp hai index như thế nào, và khi nào bitmap trở thành *lossy*.

## Problem

Trang danh mục cần thống kê và lọc sản phẩm theo category (và khoảng giá). Category 48
(Medical Supplies) có ~56k sản phẩm nằm rải rác trong 5 triệu dòng — quá nhiều cho Index Scan
từng dòng, quá ít cho Seq Scan cả bảng.

## Baseline Query

Q1 — One category: ~56k rows scattered over ~50k heap pages

```sql
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;
```

Q2 — Two indexed conditions: BitmapAnd of two indexes

```sql
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Aggregate  (cost=56042.44..56042.45 rows=1 width=40) (actual time=140.030..140.030 rows=1 loops=1)
   Buffers: shared read=50526
   ->  Bitmap Heap Scan on products  (cost=498.66..55755.77 rows=57333 width=6) (actual time=6.580..136.789 rows=55932 loops=1)
         Recheck Cond: (products.category_id = 48)
         Heap Blocks: exact=50476
         Buffers: shared read=50526
         ->  Bitmap Index Scan on idx_products_category_id  (actual time=2.470..2.470 rows=55932 loops=1)
               Index Cond: (products.category_id = 48)
               Buffers: shared read=50
 Planning Time: 0.047 ms
 Execution Time: 140.143 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Aggregate
  └── Bitmap Heap Scan on products        (2) đọc các trang heap theo thứ tự vật lý
        Recheck Cond: (category_id = 48)
        └── Bitmap Index Scan on idx_products_category_id   (1) quét index, dựng bitmap
```

1. **Bitmap Index Scan** quét index, nhưng thay vì đọc heap ngay, nó ghi TID của mọi dòng khớp
   vào một bitmap trong bộ nhớ (sắp theo block).
2. **Bitmap Heap Scan** đi qua bitmap theo thứ tự block tăng dần: mỗi trang heap được đọc **đúng
   một lần**, theo thứ tự gần tuần tự (có prefetch, `effective_io_concurrency`).
3. `Heap Blocks: exact=50476` — bitmap đủ chi tiết đến từng dòng. Nếu bitmap vượt `work_mem` nó
   chuyển sang 1 bit/trang (`lossy=`), khi đó mọi dòng của trang phải được `Recheck`.

Q2 có **hai** điều kiện đều có index:

```text
Bitmap Heap Scan
  └── BitmapAnd                        <- giao hai bitmap trong bộ nhớ
        ├── Bitmap Index Scan on idx_products_price        (36k TID)
        └── Bitmap Index Scan on idx_products_category_id  (56k TID)
```
Chỉ ~625 dòng thuộc cả hai → chỉ ~624 trang heap được đọc.

## Bottleneck

Q1 đọc ~50k trang heap cho 56k dòng: gần như mỗi dòng nằm một trang riêng (products rất rộng và
category phân bố ngẫu nhiên). Q2 phải quét hai index và giao hai bitmap lớn để lấy 625 dòng.

## Optimization Strategy A

**Composite index (category_id, price) replaces the BitmapAnd** — file [`02_optimize.sql`](02_optimize.sql)

```sql
CREATE INDEX ix_lab03_products_category_price ON products (category_id, price);
```

## Result

AFTER Strategy A — Q1:

```text
 Aggregate  (cost=1534.63..1534.64 rows=1 width=40) (actual time=4.576..4.576 rows=1 loops=1)
   Buffers: shared hit=17744
   ->  Index Only Scan using ix_lab03_products_category_price on products  (actual time=0.003..2.686 rows=55932 loops=1)
         Index Cond: (products.category_id = 48)
         Heap Fetches: 0
         Buffers: shared hit=17744
 Planning Time: 0.014 ms
 Execution Time: 4.579 ms
```

Q1: `Index Only Scan` trên index mới, Heap Fetches 0. Q2: `Index Scan` trên index mới, không còn BitmapAnd.

## Why It Improved

Index ghép `(category_id, price)`:
- Q2 trở thành **một** range scan liên tục trong index (`category_id = 48 AND price BETWEEN …`),
  không cần dựng/giao hai bitmap: nhanh hơn hàng chục lần, Buffers cũng giảm.
- Q1 (`count(*)`, `avg(price)`) trở thành **Index Only Scan**: mọi cột cần đều nằm trong index,
  không còn đọc 50k trang heap — Buffers giảm ~3 lần, thời gian giảm hàng chục lần.

## Trade-offs

- Index mới 151 MB và **chồng chéo** với `idx_products_category_id` (cùng cột đầu) — index cũ
  thành thừa (xem Lab 06/thử thách về index thừa).
- BitmapAnd không cần index ghép: hai index đơn có thể phục vụ nhiều tổ hợp điều kiện khác nhau.
  Index ghép chỉ tối ưu cho tổ hợp cụ thể.

## Optimization Strategy B

**(experiment) tiny work_mem: the planner changes plan, a forced bitmap goes lossy** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Aggregate  (cost=58121.18..58121.19 rows=1 width=40) (actual time=123.092..123.092 rows=1 loops=1)
   Buffers: shared hit=357 read=50169 written=2
   ->  Index Scan using idx_products_category_id on products  (actual time=0.034..120.275 rows=55932 loops=1)
         Index Cond: (products.category_id = 48)
         Buffers: shared hit=357 read=50169 written=2
 Planning Time: 0.046 ms
 Execution Time: 123.103 ms
```

Quan sát thực tế: với `work_mem = 64kB`, planner **không giữ bitmap** mà chuyển sang `Index Scan`
(nó đã tính trước chi phí recheck của bitmap lossy). Khi ép bitmap (tắt `enable_indexscan`), bitmap
không vừa 64 kB nên bị *lossy*: xem `Heap Blocks: lossy=` và `Rows Removed by Index Recheck` trong
log của strategy B (trên lab: `exact=207 lossy=18696`, mỗi worker recheck ~300k dòng thừa).
Chi tiết đáng suy ngẫm: plan bị ép (bitmap lossy nhưng chạy song song) lại **nhanh hơn** plan
planner tự chọn (Index Scan một luồng) — mô hình chi phí là ước lượng, không phải phép đo.
Đây là thí nghiệm — không phải tối ưu hóa.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — One category: ~56k rows scattered over ~50k heap pages**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Bitmap Heap Scan on public.products, Bitmap Index Scan on idx_products_category_id` | 1 | 0 | shared read=50526 | 140.1 ms |
| Strategy A | `Index Only Scan using ix_lab03_products_category_price on public.products` | 1 | 0 | shared hit=17744 | 4.579 ms |

**Q2 — Two indexed conditions: BitmapAnd of two indexes**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Bitmap Index Scan on idx_products_price, Bitmap Index Scan on idx_products_category_id` | 625 | 0 | shared hit=777 | 5.780 ms |
| Strategy A | `Index Scan using ix_lab03_products_category_price on public.products` | 625 | 0 | shared hit=631 | 0.167 ms |

**Strategy B — (experiment) tiny work_mem: the planner changes plan, a forced bitmap goes lossy**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q1 with work_mem = 64kB (planner free to choose) | `Index Scan using idx_products_category_id on public.products` | 1 | 0 | shared hit=357 read=50169 written=2 | 123.1 ms |
| Q1 with work_mem = 64kB and enable_indexscan = off (bitmap forced) | `Partial Aggregate, Parallel Bitmap Heap Scan on public.products, Bitmap Index Scan on idx_products_category_id` | 1 | 0 | shared read=50526 | 75.9 ms |

## Reset

```sql
DROP INDEX IF EXISTS ix_lab03_products_category_price;
RESET work_mem;
RESET enable_indexscan;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Bitmap Index Scan` (chỉ đọc index) và `Bitmap Heap Scan` (đọc heap) luôn đi cặp.
- `Heap Blocks: exact=… lossy=…`; `Rows Removed by Index Recheck`.
- `BitmapAnd` / `BitmapOr`: các bitmap con cho bạn biết mỗi index trả về bao nhiêu TID.
- Bitmap Index Scan có `actual rows` = số TID tìm được (không phải số dòng trả về cuối cùng).

## Interview Questions

1. Bitmap Heap Scan khác Index Scan ở điểm nào? Vì sao nó đọc heap hiệu quả hơn khi có nhiều dòng?
2. Recheck Cond dùng để làm gì? Khi nào nó thực sự loại bỏ dòng?
3. BitmapAnd hay index ghép — chọn cái nào, khi nào?
4. work_mem ảnh hưởng thế nào đến bitmap scan?
5. Bitmap scan có giữ được thứ tự của index không? Hệ quả với ORDER BY?

## Key Takeaways

- Bitmap scan là lựa chọn ở giữa: nhiều dòng hơn Index Scan, ít hơn Seq Scan.
- Nó đọc mỗi trang heap một lần theo thứ tự vật lý, nên chịu được dữ liệu rải rác tốt hơn Index Scan.
- BitmapAnd/BitmapOr cho phép kết hợp nhiều index đơn; index ghép nhanh hơn cho một tổ hợp cụ thể.
- Bitmap không có thứ tự: không dùng được để tránh Sort.

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
