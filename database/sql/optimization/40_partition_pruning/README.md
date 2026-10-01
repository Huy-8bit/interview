# Lab 40 · Partition pruning: scan only the relevant partitions

## Objective

Hiểu **partition pruning**: bảng phân vùng theo thời gian, pruning lúc lập plan và lúc thực thi, và giới hạn của nó.

## Problem

Báo cáo doanh thu theo tháng trên ~4.7 triệu đơn (2025-01 → 2026-09). Bảng lab `lab_orders_flat` là một
bảng thường không có index trên `created_at`: mọi báo cáo tháng đều quét cả bảng. Schema chính không bị
động tới — lab tạo bảng riêng.

## Baseline Query

Q1 — Revenue of June 2026 on the ordinary table

```sql
SELECT count(*), sum(total_amount)
FROM lab_orders_flat
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';
```

## Expected Plan

Plan quan sát được trên lab (profile 5m, PostgreSQL 16, chạy tự động bằng `scripts/test-optimization-labs.sh`, cache đã ấm):

BEFORE — Q1:

```text
 Finalize Aggregate  (cost=70009.58..70009.59 rows=1 width=40) (actual time=76.445..78.431 rows=1 loops=1)
   Buffers: shared hit=2368 read=36800
   ->  Gather  (cost=70009.35..70009.56 rows=2 width=40) (actual time=76.388..78.425 rows=3 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         Buffers: shared hit=2368 read=36800
         ->  Partial Aggregate  (cost=69009.35..69009.36 rows=1 width=40) (actual time=70.602..70.603 rows=1 loops=3)
               Buffers: shared hit=2368 read=36800
               ->  Parallel Seq Scan on lab_orders_flat  (actual time=25.931..67.793 rows=79549 loops=3)
                     Filter: ((lab_orders_flat.created_at >= '2026-06-01 00:00:00+00'::timestamp with time zone) AND (lab_orders_flat.create ...
                     Rows Removed by Filter: 1486180
                     Buffers: shared hit=2368 read=36800
 Planning Time: 0.044 ms
 Execution Time: 78.445 ms
```

> Plan thực tế phụ thuộc phiên bản PostgreSQL, phần cứng, dataset, statistics và cache. Hãy chạy `01_before.sql` và đối chiếu với plan của bạn — nếu khác, đó là một dịp tốt để tự hỏi *vì sao planner lại chọn khác*.

## How PostgreSQL Executes It

```text
lab_orders_part (partitioned, RANGE (created_at))
  ├── lab_orders_part_2025_01   FOR VALUES FROM ('2025-01-01') TO ('2025-02-01')
  ├── ...
  └── lab_orders_part_2026_09
```
- **Plan-time pruning** (Q1 sau): điều kiện là hằng số → planner chỉ đưa partition 2026_06 vào plan.
- **Runtime pruning** (Q2): mốc thời gian chỉ biết khi thực thi (subquery) → plan chứa mọi partition,
  nhưng các partition không khớp được đánh dấu `(never executed)` / `Subplans Removed`.
- Không có điều kiện trên khóa phân vùng (Q3) → `Append` quét **mọi** partition.

## Bottleneck

Bảng phẳng: Seq Scan ~4.7 triệu dòng, `Rows Removed by Filter` ~4.5 triệu để lấy ~240k dòng của tháng 6.

## Optimization Strategy A

**Range partitioning by month** — file [`02_optimize.sql`](02_optimize.sql)

```sql
-- Partitioned copy: one partition per month (2025-01 .. 2026-09)
CREATE TABLE lab_orders_part (
  id bigint NOT NULL, user_id bigint NOT NULL, status order_status NOT NULL,
  total_amount numeric(12,2) NOT NULL, created_at timestamptz NOT NULL
) PARTITION BY RANGE (created_at);

DO $$
DECLARE m date := '2025-01-01';
BEGIN
  WHILE m < '2026-10-01' LOOP
    EXECUTE format('CREATE TABLE %I PARTITION OF lab_orders_part FOR VALUES FROM (%L) TO (%L)',
                   'lab_orders_part_' || to_char(m, 'YYYY_MM'), m, (m + interval '1 month')::date);
    m := (m + interval '1 month')::date;
  END LOOP;
END $$;

INSERT INTO lab_orders_part SELECT * FROM lab_orders_flat;
ANALYZE lab_orders_part;

SELECT c.relname AS partition, pg_get_expr(c.relpartbound, c.oid) AS bounds, c.reltuples::bigint AS rows
FROM pg_inherits i JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'lab_orders_part'::regclass ORDER BY c.relname;
```

## Result

AFTER Strategy A — Q1:

```text
 Finalize Aggregate  (cost=5796.58..5796.59 rows=1 width=40) (actual time=11.790..13.045 rows=1 loops=1)
   Buffers: shared hit=1989
   ->  Gather  (cost=5796.46..5796.57 rows=1 width=40) (actual time=11.733..13.041 rows=2 loops=1)
         Workers Planned: 1
         Workers Launched: 1
         Buffers: shared hit=1989
         ->  Partial Aggregate  (cost=4796.46..4796.47 rows=1 width=40) (actual time=11.022..11.022 rows=1 loops=2)
               Buffers: shared hit=1989
               ->  Parallel Seq Scan on lab_orders_part_2026_06 lab_orders_part  (actual time=0.003..6.373 rows=119323 loops=2)
                     Filter: ((lab_orders_part.created_at >= '2026-06-01 00:00:00+00'::timestamp with time zone) AND (lab_orders_part.create ...
                     Buffers: shared hit=1989
 Planning Time: 0.048 ms
 Execution Time: 13.054 ms
```

Q1: chỉ `lab_orders_part_2026_06` trong plan. Q2: các partition khác `(never executed)`. Q3: mọi partition được quét.

## Why It Improved

Bảng phân vùng: chỉ quét partition tháng 6 (~240k dòng), Buffers ~20 lần ít hơn, nhanh hơn ~6 lần — không
cần index nào. Pruning hoạt động như một "index thô" miễn phí theo khóa phân vùng.

## Trade-offs

- Query không lọc theo khóa phân vùng chậm hơn (nhiều scan nhỏ + Append), planning chậm hơn khi có nhiều partition.
- Khóa UNIQUE / PRIMARY KEY phải chứa khóa phân vùng.
- Lợi ích vận hành thường lớn hơn lợi ích truy vấn: xoá dữ liệu cũ = `DROP TABLE partition` (tức thì, không
  bloat) thay vì `DELETE` hàng triệu dòng; VACUUM / index nhỏ theo từng partition.
- Cần tạo partition mới trước khi dữ liệu tới (hoặc có `DEFAULT` partition) — thường dùng `pg_partman`.

## Strategy Comparison

Số liệu trích tự động từ lần chạy kiểm thử (cache ấm, 1 lần chạy — chỉ để tham khảo thứ tự độ lớn; hãy ghi số của chính bạn vào [`04_compare.sql`](04_compare.sql), chạy 5–10 lần và lấy giá trị trung vị):

**Q1 — Revenue of June 2026 on the ordinary table**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Before | `Partial Aggregate, Parallel Seq Scan on public.lab_orders_flat` | 1 | 1,486,180 | shared hit=2368 read=36800 | 78.4 ms |
| Strategy A | `Partial Aggregate, Parallel Seq Scan on public.lab_orders_part_2026_06 lab_orders_part` | 1 | 0 | shared hit=1989 | 13.1 ms |

**Q2 — Query 2**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Strategy A | `Finalize Aggregate, Partial Aggregate, Parallel Seq Scan on public.lab_orders_part_2026_09, Parallel Append, Parallel Se` | 1 | 340,659 | shared hit=24926 read=2464 written=58 | 145.4 ms |

**Q3 — Query 3**

| | Plan (các node chính) | Rows trả về | Rows Removed by Filter | Buffers | Execution Time |
| --- | --- | ---: | ---: | --- | ---: |
| Strategy A | `Partial Aggregate, Parallel Append, Parallel Seq Scan on public.lab_orders_part_2026_09 lab_orders_part_21, Parallel Seq` | 1 | 4,029,771 | shared hit=30907 read=8245 written=5035 | 80.8 ms |

## Reset

```sql
DROP TABLE IF EXISTS lab_orders_part;   -- drops all its partitions
DROP TABLE IF EXISTS lab_orders_part;
DROP TABLE IF EXISTS lab_orders_flat;
RESET ALL;
```

[`05_reset.sql`](05_reset.sql) chạy các lệnh trên (idempotent) và in ra trạng thái để kiểm tra. Kiểm tra toàn bộ database: [`../00_environment/09_verify_baseline.sql`](../00_environment/09_verify_baseline.sql) phải trả về đúng một dòng `BASELINE OK`.

## What To Look For In EXPLAIN

- Tên partition trong plan (chỉ những partition không bị loại).
- `Subplans Removed: N` (initial pruning) hoặc `(never executed)` (runtime pruning).
- `Append` / `Parallel Append` với một con cho mỗi partition.

## Interview Questions

1. Partition pruning là gì? Plan-time và runtime pruning khác nhau thế nào?
2. Khi nào partitioning làm query chậm hơn?
3. Vì sao primary key của bảng phân vùng phải chứa khóa phân vùng?
4. Lợi ích vận hành của partitioning theo thời gian là gì?

## Key Takeaways

- Partitioning giúp query lọc theo khóa phân vùng và giúp vận hành (retention, VACUUM).
- Query không lọc theo khóa phân vùng phải quét mọi partition.
- Pruning có thể xảy ra cả lúc lập plan và lúc thực thi.

## Files

| File | Nội dung |
| --- | --- |
| [`01_before.sql`](01_before.sql) | query gốc + EXPLAIN / EXPLAIN ANALYZE / EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) |
| [`02_optimize.sql`](02_optimize.sql) | Strategy A |
| [`03_after.sql`](03_after.sql) | chạy lại cùng query sau khi tối ưu |
| [`04_compare.sql`](04_compare.sql) | bảng ghi số liệu trước / sau + các phép đo không phụ thuộc thời gian |
| [`05_reset.sql`](05_reset.sql) | đưa database về trạng thái trước lab |

Thứ tự: `01_before` → `02_optimize` → `03_after` → `04_compare` → `05_reset` → (`02b_…` → `03_after` → `05_reset`) … Mỗi strategy bắt đầu từ trạng thái baseline.
