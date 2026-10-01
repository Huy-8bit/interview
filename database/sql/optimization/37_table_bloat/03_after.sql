-- =============================================================================
-- Lab 37 · Table bloat: VACUUM FULL vs CLUSTER — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Full scan of the 30% remaining rows
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- Observe:
--   * Buffers = all pages of the file, though 70% of their space is empty

-- -----------------------------------------------------------------------------
-- Q2. All orders of a range of users (rows scattered over the table)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT user_id, count(*), sum(total_amount)
FROM lab_bloat
WHERE user_id BETWEEN 1000000 AND 1100000
GROUP BY user_id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT user_id, count(*), sum(total_amount)
FROM lab_bloat
WHERE user_id BETWEEN 1000000 AND 1100000
GROUP BY user_id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT user_id, count(*), sum(total_amount)
FROM lab_bloat
WHERE user_id BETWEEN 1000000 AND 1100000
GROUP BY user_id;

-- Observe:
--   * Bitmap Heap Scan: Heap Blocks = how many pages hold the matching rows

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
