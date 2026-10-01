# SQL Query Optimization Lab

41 bài thực hành tối ưu query PostgreSQL trên dataset e-commerce của lab (profile **5m**: 5 triệu users / products / orders / reviews, 10 triệu order_items), cộng 15 bài thử thách. Mỗi bài đi đúng một vòng:

```text
Query ban đầu → EXPLAIN → EXPLAIN ANALYZE → EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
  → đọc plan → bottleneck → tối ưu (Strategy A) → đo lại → so sánh → RESET
  → Strategy B (từ trạng thái ban đầu) → đo lại → RESET → …
```

Mọi plan và số liệu trong README của từng bài được **trích tự động từ lần chạy thật** trên lab này (PostgreSQL 16, Docker Desktop 8 CPU / 8 GB RAM, `shared_buffers = 256MB`, `work_mem = 8MB`). Không có plan nào được viết tay. Máy của bạn sẽ cho thời gian khác — hãy so **loại node, số dòng, số buffers**, và ghi số của chính bạn vào `04_compare.sql`.

Nhiều kết quả **không giống sách giáo khoa** — và đó là phần đáng học nhất: index được dùng nhưng chậm hơn Seq Scan (Lab 02, 12), tăng `work_mem` mà chậm hơn (Lab 22, 23), viết lại query mà không nhanh hơn (Lab 24), planner chọn plan mà plan khác lại nhanh hơn (Lab 03, 18), index "đúng sách" mà planner không thèm dùng (Lab 25, 30).

---

## 1. Bắt đầu

```bash
./scripts/generate-data.sh 5m          # nếu chưa có dataset 5m (README dự án, mục 4)
```

Mở bằng **DBeaver** (connection `localhost:5432`, database `ecommerce`) hoặc psql:

```bash
./scripts/psql.sh primary -f /dev/stdin < sql/optimization/01_seq_scan_vs_index_scan/01_before.sql
```

Trong DBeaver: *File → Open File*, chạy **từng câu** bằng Ctrl+Enter (mỗi `EXPLAIN` mở một tab kết quả), hoặc cả file bằng Alt+X. Các file chỉ chứa SQL thuần (không có lệnh `\` của psql) nên chạy được ở cả hai nơi.

Kiểm tra môi trường trước khi học: [`00_environment/`](00_environment/).

| File | Nội dung |
| --- | --- |
| [01_check_database.sql](00_environment/01_check_database.sql) | version, primary/replica, extension, profile dữ liệu đang nạp |
| [02_table_sizes.sql](00_environment/02_table_sizes.sql) | heap / index / TOAST, số dòng ước lượng |
| [03_indexes.sql](00_environment/03_indexes.sql) | mọi index: loại, unique, partial, expression, INCLUDE, kích thước, số lần dùng |
| [04_statistics.sql](00_environment/04_statistics.sql) | `pg_stats`, statistics target, extended statistics, lần ANALYZE gần nhất |
| [05_postgres_settings.sql](00_environment/05_postgres_settings.sql) | tham số ảnh hưởng plan; tham số đang bị đổi trong session |
| [06_active_queries.sql](00_environment/06_active_queries.sql) | `pg_stat_activity` dễ đọc |
| [07_index_usage.sql](00_environment/07_index_usage.sql) | `pg_stat_user_indexes`, `pg_statio_user_indexes`, `pg_indexes`, index không dùng |
| [08_table_usage.sql](00_environment/08_table_usage.sql) | `seq_scan`, `seq_tup_read`, `idx_scan`, `idx_tup_fetch`, `n_live_tup`, `n_dead_tup` |
| [09_verify_baseline.sql](00_environment/09_verify_baseline.sql) | **database có đang ở trạng thái gốc không?** → một dòng `BASELINE OK` |
| [99_reset_all_labs.sql](00_environment/99_reset_all_labs.sql) | dọn khẩn cấp mọi object của mọi lab |

## 2. Cấu trúc một bài

```text
NN_topic/
├── README.md            Objective, Problem, plan quan sát được, cách PostgreSQL thực thi, bottleneck,
│                        từng strategy + kết quả, trade-off, bảng so sánh, câu hỏi phỏng vấn, key takeaways
├── 01_before.sql        query gốc → EXPLAIN → EXPLAIN ANALYZE → EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
├── 02_optimize.sql      Strategy A
├── 02b_strategy_b.sql   Strategy B (02c… nếu có) — mỗi strategy một file, áp dụng riêng trên baseline
├── 03_after.sql         chạy lại cùng query (hoặc bản viết lại) với đủ 3 dạng EXPLAIN
├── 04_compare.sql       bảng ghi số liệu trước / sau (placeholder cho số của bạn) + phép đo kích thước
└── 05_reset.sql         đưa database về đúng trạng thái trước bài + câu kiểm tra
```

Thứ tự:

```text
01_before → 02_optimize → 03_after → 04_compare → 05_reset
          → 02b_strategy_b → 03_after → 05_reset
          → 02c_strategy_c → 03_after → 05_reset …
```

Các bài dùng bảng riêng (`lab_*`: Lab 04, 15, 35–38, 40) tạo bảng trong `01_before.sql` — chạy lại `01_before.sql` trước mỗi strategy.

## 3. Reset: không bài nào ảnh hưởng bài sau

Mọi object do lab tạo theo quy ước tên:

| Object | Tên | Ví dụ |
| --- | --- | --- |
| index | `ix_labNN_…` | `ix_lab05_products_cat_status_price` |
| extended statistics | `st_labNN_…` | `st_lab33_addr_country_city` |
| materialized view | `mv_labNN_…` | `mv_lab41_daily_revenue` |
| bảng riêng | `lab_…` | `lab_vacuum`, `lab_orders_part` |
| index của thử thách | `ix_lab99_…` | `ix_lab99_c01_phone_reversed` |

- `05_reset.sql` của mỗi bài: `DROP … IF EXISTS`, `ALTER … SET STATISTICS -1` / `RESET (n_distinct)`, `RESET ALL` (work_mem, enable_*), `ANALYZE` khi bài đã đổi statistics — chạy bao nhiêu lần cũng được.
- [`00_environment/09_verify_baseline.sql`](00_environment/09_verify_baseline.sql) so sánh với baseline: 39 index gốc, constraint, statistics target, column options, storage parameters, trigger, extended statistics, bảng/view lạ, setting của session → phải trả về **đúng một dòng `BASELINE OK`**, nếu không nó in ra câu lệnh để sửa.
- Thao tác phá hủy (UPDATE/DELETE hàng loạt, VACUUM FULL, CLUSTER, REINDEX, partition, statistics cũ) chỉ chạy trên bảng `lab_*` copy từ dữ liệu thật — **dữ liệu e-commerce chính không bị sửa**. DML trên bảng chính chỉ xuất hiện trong `BEGIN … ROLLBACK`.

Kiểm thử tự động toàn bộ (chạy từng lab theo đúng vòng ở trên, kiểm tra baseline sau mỗi reset, chạy lại `01_before` sau reset, chạy mọi strategy, chạy 15 thử thách + lời giải):

```bash
./scripts/test-optimization-labs.sh                # tất cả (~25 phút trên profile 5m)
./scripts/test-optimization-labs.sh 05 16          # chỉ vài bài
./scripts/test-optimization-labs.sh challenges     # chỉ thử thách
```

Log đầy đủ (mọi EXPLAIN) nằm trong `sql/optimization/.runs/` (git-ignored).

## 4. Lộ trình học

### Phase 1 — Hiểu EXPLAIN
Đọc mục 5 bên dưới, rồi làm Lab 01 thật chậm: chạy từng câu, đối chiếu từng con số với giải thích.

### Phase 2 — Scan

| Lab | Chủ đề |
| --- | --- |
| [01](01_seq_scan_vs_index_scan/) | Seq Scan vs Index Scan, B-tree vs hash index |
| [02](02_selectivity/) | Selectivity, MCV, cost model; partial index cho giá trị hiếm |
| [03](03_bitmap_scan/) | Bitmap Index/Heap Scan, BitmapAnd, bitmap lossy |
| [04](04_index_only_scan/) | Index Only Scan, visibility map, Heap Fetches, INCLUDE |

### Phase 3 — Index

| Lab | Chủ đề |
| --- | --- |
| [05](05_composite_index/) | Composite index cho filter + `ORDER BY … LIMIT` (cái bẫy Index Scan Backward) |
| [06](06_index_column_order/) | Thứ tự cột: equality trước, range sau, leftmost prefix |
| [07](07_covering_index/) | Covering index: INCLUDE vs key, B-tree deduplication |
| [08](08_partial_index/) | Partial index, so sánh kích thước |
| [09](09_expression_index/) | Expression index `lower(...)` |
| [10](10_function_on_indexed_column/) | Hàm trên cột (sargable), IMMUTABLE |
| [11](11_implicit_cast/) | Implicit cast vô hiệu hoá index |
| [12](12_jsonb_gin_index/) | JSONB: jsonb_ops vs jsonb_path_ops vs B-tree expression |
| [13](13_like_search/) | `LIKE 'prefix%'` (pattern_ops) vs `ILIKE '%…%'` (pg_trgm) |
| [14](14_or_condition/) | OR: BitmapOr, OR qua join → UNION |
| [15](15_index_write_cost/) | Index không miễn phí: INSERT/UPDATE/DELETE, WAL, HOT |

### Phase 4 — Join

| Lab | Chủ đề |
| --- | --- |
| [16](16_nested_loop/) | Nested Loop, loops, Memoize; khi outer lớn dần |
| [17](17_hash_join/) | Hash Join: Buckets, Batches, Memory Usage |
| [18](18_merge_join/) | Merge Join, cái giá của Sort |
| [19](19_join_optimization/) | Foreign key không index: join và DELETE |
| [20](20_large_join/) | Join 5 bảng: viết lại, covering index cho bảng rộng, song song |

### Phase 5 — Sort / Aggregation

| Lab | Chủ đề |
| --- | --- |
| [21](21_order_by_limit/) | `ORDER BY … LIMIT`: top-N heapsort vs Index Scan Backward |
| [22](22_sort_optimization/) | quicksort vs external merge vs không sort; work_mem |
| [23](23_group_by_aggregation/) | HashAggregate vs GroupAggregate, tràn đĩa |
| [24](24_distinct/) | DISTINCT, skip scan bằng recursive CTE, count(DISTINCT) |
| [25](25_window_function/) | Window function, Incremental Sort, Run Condition, DISTINCT ON |

### Phase 6 — Viết lại query

| Lab | Chủ đề |
| --- | --- |
| [26](26_cte_optimization/) | CTE inline / MATERIALIZED / NOT MATERIALIZED |
| [27](27_subquery_vs_join/) | Subquery vs JOIN, semi join, scalar subquery tương quan |
| [28](28_exists_vs_in/) | IN / EXISTS / NOT IN / NOT EXISTS, bẫy NULL |
| [29](29_pagination_offset/) | OFFSET sâu, deferred join |
| [30](30_keyset_pagination/) | Keyset pagination |
| [31](31_query_rewrite/) | count > 0 → EXISTS, HAVING → WHERE, UNION ALL, SELECT * |

### Phase 7 — Statistics / Planner

| Lab | Chủ đề |
| --- | --- |
| [32](32_statistics/) | `pg_stats`, n_distinct, SET STATISTICS, ghim n_distinct |
| [33](33_cardinality_estimation/) | Cột tương quan, CREATE STATISTICS dependencies / mcv |
| [34](34_extended_statistics_ndistinct/) | ndistinct cho GROUP BY nhiều cột |
| [35](35_analyze_stale_statistics/) | Statistics cũ, ANALYZE |

### Phase 8 — Maintenance

| Lab | Chủ đề |
| --- | --- |
| [36](36_vacuum/) | Dead tuple, visibility map, VACUUM vs VACUUM FULL, hot_standby_feedback |
| [37](37_table_bloat/) | Table bloat: VACUUM FULL vs CLUSTER |
| [38](38_index_bloat/) | Index bloat: pgstatindex, REINDEX (CONCURRENTLY) |
| [39](39_buffer_cache/) | shared hit vs read, cold vs warm, working set, pg_buffercache |

### Phase 9 — Nâng cao

| Lab | Chủ đề |
| --- | --- |
| [40](40_partition_pruning/) | Partition pruning lúc lập plan và lúc thực thi |
| [41](41_materialized_view/) | Materialized view, REFRESH CONCURRENTLY |
| [99](99_challenges/) | 15 thử thách không kèm lời giải (lời giải riêng trong `solutions/`) |

## 5. Đọc EXPLAIN

### EXPLAIN không chạy query — EXPLAIN ANALYZE thì có

| Lệnh | Thực thi query? | Cho biết |
| --- | --- | --- |
| `EXPLAIN q` | **không** | plan + ước lượng (cost, rows, width) |
| `EXPLAIN ANALYZE q` | **có** | + thời gian thật, số dòng thật, loops |
| `EXPLAIN (ANALYZE, BUFFERS) q` | có | + trang 8 KB đọc từ đâu |
| `EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS) q` | có | + cột output, tên schema, tham số khác mặc định |
| `EXPLAIN (ANALYZE, BUFFERS, WAL) dml` | có | + lượng WAL sinh ra |

`EXPLAIN ANALYZE` một câu `INSERT/UPDATE/DELETE` **thực sự sửa dữ liệu**. Luôn bọc:

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS, WAL) UPDATE orders SET status = status WHERE id = 1;
ROLLBACK;
```

Ngược lại, khi nghi một query có thể chạy rất lâu, chỉ dùng `EXPLAIN` (Lab 28: `NOT IN` với plan O(N×M) chỉ được EXPLAIN, không bao giờ chạy).

### Đọc cây từ trong ra ngoài

```text
Limit
  └── Sort
        └── Hash Join
              ├── Seq Scan on orders          (probe side)
              └── Hash
                    └── Seq Scan on users     (build side)
```

PostgreSQL thực thi:

```text
Seq Scan users → build hash table → Seq Scan orders → probe hash table → Hash Join → Sort → Limit
```

Node thụt sâu nhất chạy trước và đẩy dòng lên cha. Với join, con **thứ nhất** là outer/probe, con **thứ hai** là inner/build (Hash) hoặc phía được tra lại mỗi vòng (Nested Loop).

### Các trường

| Trường | Ý nghĩa |
| --- | --- |
| `cost=startup..total` | ước lượng chi phí (đơn vị tùy ý ≈ 1 trang đọc tuần tự = 1.0). **Không phải ms.** startup = trước khi trả dòng đầu tiên (Sort, Hash có startup cao); total = trả hết dòng |
| `rows=` | số dòng **ước lượng** node trả về (mỗi loop) |
| `width=` | độ rộng trung bình (byte) mỗi dòng ước lượng |
| `actual time=a..b` | ms tới dòng đầu tiên .. tới khi xong, **trung bình mỗi loop** |
| `actual rows=` | số dòng **thật**, trung bình mỗi loop |
| `loops=` | số lần node chạy; tổng dòng = rows × loops; với plan song song, `loops=3` = 2 worker + leader |
| `Index Cond` | điều kiện dùng để **đi vào** index (seek / range) |
| `Filter` | điều kiện kiểm tra **sau** khi đã đọc dòng |
| `Rows Removed by Filter` | số dòng đọc rồi vứt (mỗi loop) — ứng viên cho index |
| `Join Filter` | điều kiện kiểm tra sau khi hai dòng đã khớp theo khóa join |
| `Recheck Cond` / `Rows Removed by Index Recheck` | bitmap scan kiểm tra lại dòng (trang lossy) |
| `Heap Fetches` | Index Only Scan phải đọc heap (trang chưa all-visible) |
| `Sort Method` / `Memory` / `Disk` | quicksort (RAM), external merge (đĩa), top-N heapsort (có LIMIT) |
| `Buckets` / `Batches` / `Memory Usage` | bảng băm của Hash; Batches > 1 = tràn đĩa |
| `Batches` / `Disk Usage` trên HashAggregate | aggregate tràn đĩa (PG13+) |
| `Buffers: shared hit` | trang đã có trong `shared_buffers` |
| `Buffers: shared read` | trang PostgreSQL phải xin từ OS (từ **OS page cache** hoặc đĩa — EXPLAIN không phân biệt) |
| `shared dirtied` / `written` | trang bị sửa / bị ghi ra trong lúc chạy query |
| `temp read` / `written` | file tạm (sort/hash tràn đĩa) |
| `Planning Time` / `Execution Time` | thời gian lập plan / thực thi (không gồm gửi kết quả về client) |
| `Workers Planned` / `Launched` | parallel query |
| `Memoize: Hits / Misses / Evictions` | cache kết quả lookup của Nested Loop (PG14+) |

### Estimated rows vs actual rows

So `rows=` với `actual rows × loops` ở **từng** node. Lệch trên ~10 lần là dấu hiệu quan trọng nhất trong một plan:

- planner ước lượng ít dòng → chọn Nested Loop, Index Scan, không song song… → thực tế nhiều dòng → chậm (Lab 33, 35).
- ước lượng nhiều dòng → cấp bộ nhớ / chọn Hash cho tập nhỏ — thường ít tai hại hơn.

Nguyên nhân thường gặp: statistics cũ (Lab 35), cột tương quan (Lab 33), hàm/biểu thức không có statistics (Lab 10), n_distinct sai (Lab 32), giả định phân bố đều dưới LIMIT (Lab 05).

### Bộ câu hỏi khi đọc một plan

1. Node nào bắt đầu? Bảng nào bị Seq Scan?
2. Planner ước lượng bao nhiêu dòng, thực tế bao nhiêu? Lệch ở đâu?
3. Filter loại bỏ bao nhiêu dòng?
4. Đọc bao nhiêu trang? hit hay read?
5. Loại join là gì, vì sao planner chọn nó?
6. Có Sort không? Trong RAM hay ra đĩa?
7. Có index không? Index có thực sự giảm số trang đọc không (`Index Cond` vs quét toàn bộ index)?
8. Có thể dùng composite / covering / partial index không? Thứ tự cột?
9. Có thể viết lại query không?
10. Tối ưu tốn bao nhiêu dung lượng? Làm chậm ghi bao nhiêu?

## 6. Benchmark đúng cách

- **Chạy 5–10 lần**, lấy trung vị. Một lần chạy không nói lên gì.
- **Cold vs warm cache**: lần đầu thường có nhiều `shared read` (trang được đưa vào cache), các lần sau là `hit`. Lần chạy thứ hai nhanh hơn **không có nghĩa** là plan tốt hơn — có thể chỉ là dữ liệu đã được cache. Không cần (và không nên) xoá cache của OS bằng quyền root: chỉ cần chạy nhiều lần và đọc Buffers.
- **Phân biệt cải thiện plan với hiệu ứng cache**: plan tốt hơn làm **tổng** Buffers (hit + read) giảm; cache chỉ chuyển read thành hit (Lab 39).
- Working set lớn hơn `shared_buffers` (256 MB trên lab) → lần chạy nào cũng `read` (Lab 39). Kết quả của bạn sẽ khác nếu cấu hình khác.
- Ghi lại cả Execution Time **và** Buffers trong `04_compare.sql`.
- `\timing on` trong psql đo cả thời gian mạng + client; `Execution Time` của EXPLAIN ANALYZE thì không — và EXPLAIN ANALYZE thêm chi phí đo đạc (`TIMING OFF` để giảm).

## 7. Index không miễn phí

Mỗi index giúp một số SELECT nhưng:

- làm **INSERT** chậm hơn (thêm một entry cho mỗi index),
- làm **UPDATE** chậm hơn (và chặn HOT update nếu cột được cập nhật nằm trong index),
- **DELETE** để lại entry chết cần VACUUM dọn,
- tăng **dung lượng** (Lab 07: covering index lớn gấp 4 lần index thường),
- tăng **WAL** → tăng tải replication, backup, PITR (Lab 15: 4 index phụ → WAL INSERT tăng ~1.8 lần, thời gian ~3 lần),
- tăng chi phí **bảo trì** (VACUUM, REINDEX, bloat — Lab 38).

Mọi lab có tạo index đều in kích thước (`pg_relation_size`, `pg_indexes_size`, `pg_total_relation_size`). Định kỳ tìm index không dùng: [`00_environment/07_index_usage.sql`](00_environment/07_index_usage.sql).

## 8. Liên quan

- [docs/index-lab.md](../../docs/index-lab.md), [docs/query-optimization-lab.md](../../docs/query-optimization-lab.md) — phiên bản ngắn gọn trên dataset **default** (100k users).
- [docs/transaction-lab.md](../../docs/transaction-lab.md), [docs/mvcc-lab.md](../../docs/mvcc-lab.md) — MVCC, lock, transaction dài chặn VACUUM.
- [docs/monitoring.md](../../docs/monitoring.md) — `pg_stat_statements`, tìm query chậm trên hệ thống thật.
