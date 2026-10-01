-- =============================================================================
-- Lab 31 · Query rewrites: count > 0, HAVING, UNION, SELECT * — AFTER
-- The four rewritten queries.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. EXISTS instead of count(*) > 0
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT EXISTS (SELECT 1 FROM orders WHERE status = 'PENDING') AS has_pending;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT EXISTS (SELECT 1 FROM orders WHERE status = 'PENDING') AS has_pending;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT EXISTS (SELECT 1 FROM orders WHERE status = 'PENDING') AS has_pending;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT EXISTS (SELECT 1 FROM orders WHERE status = 'PENDING') AS has_pending;

-- Observe:
--   * Limit / InitPlan that stops after the first row

-- -----------------------------------------------------------------------------
-- Q2. Filter in WHERE
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT status, count(*)
FROM orders
WHERE status IN ('PENDING', 'CONFIRMED')
GROUP BY status;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT status, count(*)
FROM orders
WHERE status IN ('PENDING', 'CONFIRMED')
GROUP BY status;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT status, count(*)
FROM orders
WHERE status IN ('PENDING', 'CONFIRMED')
GROUP BY status;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT status, count(*)
FROM orders
WHERE status IN ('PENDING', 'CONFIRMED')
GROUP BY status;

-- Observe:
--   * Same plan as the HAVING version (the planner had pushed it down already)

-- -----------------------------------------------------------------------------
-- Q3. UNION ALL (duplicates allowed)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT user_id FROM orders  WHERE created_at >= '2026-09-30'
UNION ALL
SELECT user_id FROM reviews WHERE created_at >= '2026-09-30';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT user_id FROM orders  WHERE created_at >= '2026-09-30'
UNION ALL
SELECT user_id FROM reviews WHERE created_at >= '2026-09-30';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT user_id FROM orders  WHERE created_at >= '2026-09-30'
UNION ALL
SELECT user_id FROM reviews WHERE created_at >= '2026-09-30';

-- -----------------------------------------------------------------------------
-- Q4. Only the needed columns
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, total_amount
FROM orders
WHERE created_at >= '2026-09-30'
ORDER BY total_amount DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, total_amount
FROM orders
WHERE created_at >= '2026-09-30'
ORDER BY total_amount DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, total_amount
FROM orders
WHERE created_at >= '2026-09-30'
ORDER BY total_amount DESC;

-- Observe:
--   * Sort Memory much smaller than with SELECT *

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
