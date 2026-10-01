-- =============================================================================
-- Lab 35 · Stale statistics and ANALYZE — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Recent orders: the histogram does not know they exist
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- Observe:
--   * rows= estimate (tiny) vs actual rows (400k): created_at is beyond the histogram's
--   * last bucket, so the planner thinks almost nothing matches

-- -----------------------------------------------------------------------------
-- Q2. The bad estimate drives the join strategy
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- Observe:
--   * Nested Loop with loops = 400k index lookups into users, chosen because the outer side
--   * was estimated at a handful of rows

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
