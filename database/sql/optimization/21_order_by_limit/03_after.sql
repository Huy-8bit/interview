-- =============================================================================
-- Lab 21 · ORDER BY ... LIMIT: top-N heapsort vs Index Scan Backward — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
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

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
