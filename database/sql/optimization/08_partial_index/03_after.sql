-- =============================================================================
-- Lab 08 · Partial index: index only the rows you query — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Reconciliation job: oldest 100 PENDING payments before a cutoff
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'PENDING'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'PENDING'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'PENDING'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'PENDING'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- Observe:
--   * Parallel Seq Scan + top-N heapsort over the whole table to return 100 rows

-- -----------------------------------------------------------------------------
-- Q2. Same shape, another status (FAILED)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'FAILED'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'FAILED'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'FAILED'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_id, amount, created_at
FROM payments
WHERE status = 'FAILED'
  AND created_at < '2026-09-01'
ORDER BY created_at
LIMIT 100;

-- Observe:
--   * A partial index WHERE status = 'PENDING' can NOT be used here

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
