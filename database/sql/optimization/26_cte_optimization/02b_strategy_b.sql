-- =============================================================================
-- Lab 26 · CTE: inlined, MATERIALIZED, NOT MATERIALIZED — OPTIMIZE · Strategy B
-- Strategy B: (experiment) NOT MATERIALIZED on the CTE that is used twice
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- NOT MATERIALIZED forces inlining: each reference becomes its own copy of the
-- subquery, so the 'per customer' aggregation over September's orders runs
-- twice. Inlining is not always better.

-- -----------------------------------------------------------------------------
-- Q2 with AS NOT MATERIALIZED
-- -----------------------------------------------------------------------------

-- 1) The query itself
WITH user_totals AS NOT MATERIALIZED (
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
WITH user_totals AS NOT MATERIALIZED (
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
WITH user_totals AS NOT MATERIALIZED (
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
WITH user_totals AS NOT MATERIALIZED (
  SELECT user_id, sum(total_amount) AS spent
  FROM orders
  WHERE created_at >= '2026-09-01'
  GROUP BY user_id
)
SELECT count(*) AS above_average_customers
FROM user_totals
WHERE spent > (SELECT avg(spent) FROM user_totals);

-- Observe:
--   * The GROUP BY user_id subtree appears twice in the plan

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
