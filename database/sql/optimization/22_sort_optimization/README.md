# Lab 22 · Sort: in-memory quicksort vs external merge vs no sort

## Objective

Hiểu **Sort**: quicksort trong bộ nhớ, external merge ra đĩa, top-N heapsort — và cách tốt nhất là không cần sort.

## Problem

Xuất 5 triệu đơn theo số tiền giảm dần (và top 100). `work_mem` mặc định của lab là 8MB.

## Baseline Query

Q1 — All 5M orders by amount (result not fetched to the client)

```sql
SELECT id, user_id, total_amount
FROM orders
ORDER BY total_amount DESC;
```

Q2 — Top 100 orders by amount

```sql
SELECT id, user_id, total_amount
    FROM orders
    ORDER BY total_amount DESC
LIMIT 100;
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Sort  (cost=866506.75..879008.11 rows=5000547 width=22) (actual time=1931.291..2137.312 rows=5000000 loops=1)
   Sort Key: orders.total_amount DESC
   Sort Method: external merge  Disk: 161480kB
   Buffers: shared hit=66 read=199966, temp read=40356 written=40400
   ->  Seq Scan on orders  (cost=0.00..250037.47 rows=5000547 width=22) (actual time=9.519..501.350 rows=5000000 loops=1)
         Buffers: shared hit=66 read=199966
 Planning Time: 0.105 ms
 Execution Time: 2222.330 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
Sort   Sort Key: total_amount DESC
       Sort Method: external merge  Disk: 161480kB     <- không vừa work_mem: chia run, ghi đĩa, merge
  └── Seq Scan on orders
```
- **quicksort**: toàn bộ dữ liệu vừa `work_mem` → sort trong RAM.
- **external merge**: chia thành các đoạn vừa bộ nhớ, sort từng đoạn, ghi file tạm, rồi merge.
- **top-N heapsort**: có LIMIT → chỉ giữ N dòng tốt nhất (Q2: vài chục KB).
`EXPLAIN ANALYZE` thực thi sort đầy đủ nhưng không gửi 5 triệu dòng về client.

## Bottleneck

Q1: sort 5 triệu dòng, ~160MB ghi ra đĩa tạm.

## Optimization Strategy A

**(experiment) work_mem = 512MB for this session** — file [`02_optimize.sql`](02_optimize.sql)

## Result

AFTER Strategy A — Q1:

```text
 Sort  (cost=806439.70..818941.06 rows=5000547 width=22) (actual time=1498.402..2121.616 rows=5000000 loops=1)
   Sort Key: orders.total_amount DESC
   Sort Method: quicksort  Memory: 409141kB
   Buffers: shared hit=418 read=199614
   ->  Seq Scan on orders  (cost=0.00..250037.47 rows=5000547 width=22) (actual time=7.346..354.823 rows=5000000 loops=1)
         Buffers: shared hit=418 read=199614
 Planning Time: 0.057 ms
 Execution Time: 2200.513 ms
```

`Sort Method: quicksort  Memory: ~409MB` — thời gian gần như không đổi.

## Why It Improved

- Strategy A (`work_mem = 512MB`): sort thành **quicksort trong RAM (~409MB)** nhưng trên lab **không nhanh
  hơn** external merge — với SSD và OS cache, ghi/đọc file tạm rẻ hơn ta nghĩ, còn sort 400MB trong RAM
  vẫn tốn CPU. Đồng thời một query chiếm 400MB RAM.
- Strategy B (index `(total_amount DESC) INCLUDE (id, user_id)`): **không còn Sort** — Index Only Scan
  trả dòng đã sắp, nhanh hơn ~7 lần cho Q1; Q2 chỉ đọc 100 entry.

## Trade-offs

- `work_mem` là bộ nhớ cho **mỗi** node sort/hash, **mỗi** query, **mỗi** process: 100 kết nối × vài node
  × 512MB là hết RAM. Chỉ tăng theo session/transaction (`SET LOCAL`).
- Index sắp sẵn tốn dung lượng và chi phí ghi; đáng giá khi thứ tự đó được dùng thường xuyên.

## Optimization Strategy B

**Index that already provides the order: (total_amount DESC) INCLUDE (id, user_id)** — file [`02b_strategy_b.sql`](02b_strategy_b.sql)

```sql
CREATE INDEX ix_lab22_orders_amount_incl ON orders (total_amount DESC) INCLUDE (id, user_id);
VACUUM (ANALYZE) orders;
```

## Result (Strategy B)

AFTER Strategy B — Q1:

```text
 Index Only Scan using ix_lab22_orders_amount_incl on orders  (actual time=0.624..239.947 rows=5000000 loops=1)
   Heap Fetches: 0
   Buffers: shared hit=613594
 Planning Time: 0.054 ms
 Execution Time: 316.920 ms
```

`Index Only Scan using ix_lab22_orders_amount_incl`, Heap Fetches 0, không có node Sort.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — All 5M orders by amount (result not fetched to the client)**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Seq Scan on public.orders` | 5000000 | 0 | shared hit=66 read=199966, temp read=40356 written=40400 | 2,222.3 ms |
| Strategy B | `Index Only Scan using ix_lab22_orders_amount_incl on public.orders` | 5000000 | 0 | shared hit=613594 | 316.9 ms |

**Q2 — Top 100 orders by amount**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Sort, Parallel Seq Scan on public.orders` | 100 | 0 | shared hit=362 read=199742 | 233.8 ms |
| Strategy B | `Index Only Scan using ix_lab22_orders_amount_incl on public.orders` | 100 | 0 | shared hit=91 | 0.021 ms |

**Strategy A — (experiment) work_mem = 512MB for this session**

| Query | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Q1 with work_mem = 512MB | `Seq Scan on public.orders` | 5000000 | 0 | shared hit=418 read=199614 | 2,200.5 ms |

## Reset

```sql
RESET work_mem;
DROP INDEX IF EXISTS ix_lab22_orders_amount_incl;
ANALYZE orders;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- `Sort Method:` quicksort / external merge / top-N heapsort; `Memory:` / `Disk:`.
- `Buffers: temp read=… written=…`.
- Log server: `log_temp_files` (lab bật ở 10MB) ghi lại các sort tràn đĩa.

## Interview Questions

1. Ba Sort Method của PostgreSQL là gì? Khi nào mỗi cái xuất hiện?
2. Vì sao không nên tăng work_mem toàn cục lên rất lớn?
3. Làm sao tránh hoàn toàn một node Sort?
4. External merge có luôn chậm hơn quicksort không?

## Key Takeaways

- Sort nhanh nhất là sort không xảy ra: index đúng thứ tự (+ covering).
- Tăng work_mem đổi đĩa lấy RAM — không phải lúc nào cũng nhanh hơn.
- LIMIT nhỏ biến sort thành top-N heapsort với bộ nhớ không đáng kể.

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
