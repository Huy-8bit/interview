-- =============================================================================
-- Lab 24 · DISTINCT: full scan vs emulated skip scan, count(DISTINCT) — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Which categories have products? (40 values among 5M rows)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT DISTINCT category_id
FROM products;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT DISTINCT category_id
FROM products;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT DISTINCT category_id
FROM products;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT DISTINCT category_id
FROM products;

-- Observe:
--   * Unique over a (Parallel) Index Only Scan of the WHOLE category index: 5M entries
--   * read to output 40 values

-- -----------------------------------------------------------------------------
-- Q2. How many distinct customers ordered since September?
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(DISTINCT user_id)
FROM orders
WHERE created_at >= '2026-09-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(DISTINCT user_id)
FROM orders
WHERE created_at >= '2026-09-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(DISTINCT user_id)
FROM orders
WHERE created_at >= '2026-09-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(DISTINCT user_id)
FROM orders
WHERE created_at >= '2026-09-01';

-- Observe:
--   * count(DISTINCT ...) is computed by an Aggregate that SORTS its input internally:
--   * the sort does not appear as a plan node and the aggregate cannot run in parallel

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
