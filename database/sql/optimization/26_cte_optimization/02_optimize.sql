-- =============================================================================
-- Lab 26 · CTE: inlined, MATERIALIZED, NOT MATERIALIZED — OPTIMIZE · Strategy A
-- Strategy A: (experiment) AS MATERIALIZED on the single-use CTE
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- MATERIALIZED restores the pre-PG12 'optimization fence': the CTE is computed
-- completely and stored, and outer conditions are NOT pushed into it. Here that
-- means reading every order since August to keep one row.

-- -----------------------------------------------------------------------------
-- Q1 with AS MATERIALIZED
-- -----------------------------------------------------------------------------

-- 1) The query itself
WITH recent AS MATERIALIZED (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 4900533;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
WITH recent AS MATERIALIZED (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 4900533;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
WITH recent AS MATERIALIZED (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 4900533;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
WITH recent AS MATERIALIZED (
  SELECT * FROM orders WHERE created_at >= '2026-08-01'
)
SELECT id, status, total_amount
FROM recent
WHERE user_id = 4900533;

-- Observe:
--   * CTE Scan on recent + Filter: Rows Removed by Filter = all of August/September

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
