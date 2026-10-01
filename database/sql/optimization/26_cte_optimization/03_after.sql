-- =============================================================================
-- Lab 26 · CTE: inlined, MATERIALIZED, NOT MATERIALIZED — AFTER
-- The baseline queries again: here the planner's default is already the best choice.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. CTE referenced once: inlined by the planner (PostgreSQL 12+)
-- -----------------------------------------------------------------------------

-- 1) The query itself
WITH recent AS (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 2732269;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
WITH recent AS (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 2732269;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
WITH recent AS (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 2732269;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
WITH recent AS (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 2732269;

-- Observe:
--   * No 'CTE recent' node: the CTE was inlined, the user_id condition reached
--   * orders and idx_orders_user_id is used

-- -----------------------------------------------------------------------------
-- Q2. CTE referenced twice: computed once (materialized) by default
-- -----------------------------------------------------------------------------

-- 1) The query itself
WITH user_totals AS (
  SELECT user_id, sum(total_amount) AS spent
  FROM orders
  WHERE created_at >= '2026-09-01'
  GROUP BY user_id
)
SELECT count(*) AS above_average_customers
FROM user_totals
WHERE spent > (SELECT avg(spent) FROM user_totals);

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
WITH user_totals AS (
  SELECT user_id, sum(total_amount) AS spent
  FROM orders
  WHERE created_at >= '2026-09-01'
  GROUP BY user_id
)
SELECT count(*) AS above_average_customers
FROM user_totals
WHERE spent > (SELECT avg(spent) FROM user_totals);

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
WITH user_totals AS (
  SELECT user_id, sum(total_amount) AS spent
  FROM orders
  WHERE created_at >= '2026-09-01'
  GROUP BY user_id
)
SELECT count(*) AS above_average_customers
FROM user_totals
WHERE spent > (SELECT avg(spent) FROM user_totals);

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
WITH user_totals AS (
  SELECT user_id, sum(total_amount) AS spent
  FROM orders
  WHERE created_at >= '2026-09-01'
  GROUP BY user_id
)
SELECT count(*) AS above_average_customers
FROM user_totals
WHERE spent > (SELECT avg(spent) FROM user_totals);

-- Observe:
--   * 'CTE user_totals' node computed once, then two CTE Scans read the stored result

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
