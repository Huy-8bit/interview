-- =============================================================================
-- Lab 03 · Bitmap Index Scan + Bitmap Heap Scan, BitmapAnd — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
-- Category 48 = Medical Supplies (~56k of 5M products): matching rows are spread over the whole table
SELECT category_id, count(*) FROM products WHERE category_id = 48 GROUP BY 1;
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;

-- -----------------------------------------------------------------------------
-- Q1. One category: ~56k rows scattered over ~50k heap pages
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- Observe:
--   * Bitmap Index Scan on idx_products_category_id: builds a bitmap of matching TIDs
--   * Bitmap Heap Scan: reads each heap page once, in physical order
--   * Heap Blocks: exact=N (one bit per row)  vs  lossy=N (one bit per page)
--   * Recheck Cond: only evaluated on lossy pages (or for lossy index types)

-- -----------------------------------------------------------------------------
-- Q2. Two indexed conditions: BitmapAnd of two indexes
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- Observe:
--   * BitmapAnd: two Bitmap Index Scans combined in memory before touching the heap
--   * Each child scan returns many TIDs (actual rows=...), the AND keeps only a few

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
