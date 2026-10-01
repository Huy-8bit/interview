-- =============================================================================
-- Lab 41 · Materialized view: precompute an expensive aggregate — AFTER
-- The dashboard served from the materialized view.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Daily revenue from the materialized view
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT day, orders, revenue
FROM mv_lab41_daily_revenue
WHERE status = 'COMPLETED'
  AND day >= '2026-07-01' AND day < '2026-10-01'
ORDER BY day;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT day, orders, revenue
FROM mv_lab41_daily_revenue
WHERE status = 'COMPLETED'
  AND day >= '2026-07-01' AND day < '2026-10-01'
ORDER BY day;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT day, orders, revenue
FROM mv_lab41_daily_revenue
WHERE status = 'COMPLETED'
  AND day >= '2026-07-01' AND day < '2026-10-01'
ORDER BY day;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT day, orders, revenue
FROM mv_lab41_daily_revenue
WHERE status = 'COMPLETED'
  AND day >= '2026-07-01' AND day < '2026-10-01'
ORDER BY day;

-- Observe:
--   * Index Scan on the MV's unique index over ~90 rows instead of aggregating 5M orders

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
