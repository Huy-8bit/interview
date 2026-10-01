-- =============================================================================
-- Lab 21 · ORDER BY ... LIMIT: top-N heapsort vs Index Scan Backward — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Latest 50 payments
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_id, amount, status, created_at
FROM payments
ORDER BY created_at DESC
LIMIT 50;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_id, amount, status, created_at
FROM payments
ORDER BY created_at DESC
LIMIT 50;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_id, amount, status, created_at
FROM payments
ORDER BY created_at DESC
LIMIT 50;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_id, amount, status, created_at
FROM payments
ORDER BY created_at DESC
LIMIT 50;

-- Observe:
--   * Parallel Seq Scan of ALL payments + Sort (top-N heapsort) per worker + Gather Merge
--   * top-N heapsort keeps only the best 50 rows in memory: cheap in RAM, but every row is read

-- -----------------------------------------------------------------------------
-- Q2. Latest 50 FAILED payments
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_id, amount, status, created_at
FROM payments
WHERE status = 'FAILED'
ORDER BY created_at DESC
LIMIT 50;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_id, amount, status, created_at
FROM payments
WHERE status = 'FAILED'
ORDER BY created_at DESC
LIMIT 50;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_id, amount, status, created_at
FROM payments
WHERE status = 'FAILED'
ORDER BY created_at DESC
LIMIT 50;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_id, amount, status, created_at
FROM payments
WHERE status = 'FAILED'
ORDER BY created_at DESC
LIMIT 50;

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
