-- =============================================================================
-- Lab 32 · Planner statistics: n_distinct, MCV, histogram, correlation — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. GROUP BY user_id: how many groups does the planner expect?
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT user_id, count(*)
FROM orders
GROUP BY user_id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT user_id, count(*)
FROM orders
GROUP BY user_id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT user_id, count(*)
FROM orders
GROUP BY user_id;

-- Observe:
--   * rows= on the aggregate node = the planner's n_distinct estimate; actual rows = real groups
--   * A wrong group count changes memory decisions (HashAggregate vs GroupAggregate, batches)

-- -----------------------------------------------------------------------------
-- Q2. Equality on one user_id: selectivity of a value NOT in the MCV list
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE user_id = 2215979;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE user_id = 2215979;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE user_id = 2215979;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE user_id = 2215979;

-- Observe:
--   * estimated rows ~ (1 - sum(MCV freqs) - null_frac) / (n_distinct - n_MCV) x reltuples

-- -----------------------------------------------------------------------------
-- Q3. Range on total_amount: estimated from the histogram
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- Observe:
--   * Seq Scan rows= comes from the fraction of histogram buckets covering [100, 105]

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
