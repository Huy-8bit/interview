-- =============================================================================
-- Lab 08 · Partial index: index only the rows you query — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT status, count(*) FROM payments GROUP BY status ORDER BY 2 DESC;
SELECT count(*) AS pending_older_than_cutoff FROM payments WHERE status = 'PENDING' AND created_at < '2026-09-01';

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
