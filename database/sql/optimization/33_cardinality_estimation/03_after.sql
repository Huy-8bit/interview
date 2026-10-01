-- =============================================================================
-- Lab 33 · Cardinality estimation: correlated columns and CREATE STATISTICS — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Addresses in Hanoi, Vietnam (two correlated columns)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- Observe:
--   * rows= estimate vs actual: the planner assumes independence,
--   * P(VN and Hanoi) = P(VN) x P(Hanoi), but every Hanoi address IS in VN

-- -----------------------------------------------------------------------------
-- Q2. The estimate feeds a join: orders shipped to default addresses in Hanoi
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- Observe:
--   * The underestimated outer side makes a Nested Loop look cheap: check loops= on the inner node

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
