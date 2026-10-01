-- =============================================================================
-- Lab 28 · EXISTS vs IN, NOT EXISTS vs NOT IN (and the NULL trap) — OPTIMIZE · Strategy A
-- Strategy A: (experiment) NOT IN when it works - and the NULL trap
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- With a small subquery result NOT IN becomes a 'hashed SubPlan' and is fast. But
-- NOT IN has SQL three-valued logic: if the subquery returns a single NULL,
-- 'x NOT IN (..., NULL)' is never TRUE and the query returns nothing.
-- NOT EXISTS has neither problem.

-- -----------------------------------------------------------------------------
-- Q1. NOT IN against a small set (hashed SubPlan)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28');

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28');

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28');

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28');

-- Observe:
--   * Filter: (NOT (hashed SubPlan 1))

-- -----------------------------------------------------------------------------
-- Q2. The NULL trap: one NULL in the subquery -> 0 rows
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28'
                   UNION ALL SELECT NULL);

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28'
                   UNION ALL SELECT NULL);

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28'
                   UNION ALL SELECT NULL);

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND u.id NOT IN (SELECT o.user_id FROM orders o WHERE o.created_at >= '2026-09-28'
                   UNION ALL SELECT NULL);

-- Observe:
--   * count = 0 although thousands of users qualify

-- Undo only this strategy:
-- -- (nothing to undo: queries only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
