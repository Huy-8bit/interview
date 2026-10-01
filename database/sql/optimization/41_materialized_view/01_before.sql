-- =============================================================================
-- Lab 41 · Materialized view: precompute an expensive aggregate — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Daily revenue dashboard (Q3 2026) computed from 5M orders
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
       count(*)          AS orders,
       sum(total_amount) AS revenue
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-07-01' AND created_at < '2026-10-01'
GROUP BY 1
ORDER BY 1;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
       count(*)          AS orders,
       sum(total_amount) AS revenue
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-07-01' AND created_at < '2026-10-01'
GROUP BY 1
ORDER BY 1;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
       count(*)          AS orders,
       sum(total_amount) AS revenue
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-07-01' AND created_at < '2026-10-01'
GROUP BY 1
ORDER BY 1;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT (created_at AT TIME ZONE 'UTC')::date AS day,
       count(*)          AS orders,
       sum(total_amount) AS revenue
FROM orders
WHERE status = 'COMPLETED'
  AND created_at >= '2026-07-01' AND created_at < '2026-10-01'
GROUP BY 1
ORDER BY 1;

-- Observe:
--   * Scans and aggregates hundreds of thousands of orders on every page load

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
