-- =============================================================================
-- Lab 29 · Pagination with OFFSET: the cost of deep pages — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Page 1 (OFFSET 0)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 0;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 0;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 0;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 0;

-- -----------------------------------------------------------------------------
-- Q2. Page 2,001 (OFFSET 100,000)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 100000;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 100000;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 100000;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 100000;

-- -----------------------------------------------------------------------------
-- Q3. Page 20,001 (OFFSET 1,000,000)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 1000000;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 1000000;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 1000000;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC
LIMIT 50 OFFSET 1000000;

-- Observe:
--   * Index Scan Backward with actual rows = OFFSET + 50: every skipped row is still
--   * fetched from the heap and then thrown away by the Limit

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
