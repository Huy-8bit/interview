-- =============================================================================
-- Lab 27 · Subquery vs JOIN: what the planner rewrites for you — AFTER
-- Q1 unchanged (already optimal) and Q2 rewritten as one grouped LEFT JOIN.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Q1 unchanged
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id
               FROM orders o
               JOIN order_items i ON i.order_id = o.id
               WHERE i.product_id = 1986295);

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id
               FROM orders o
               JOIN order_items i ON i.order_id = o.id
               WHERE i.product_id = 1986295);

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id
               FROM orders o
               JOIN order_items i ON i.order_id = o.id
               WHERE i.product_id = 1986295);

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users u
WHERE u.id IN (SELECT o.user_id
               FROM orders o
               JOIN order_items i ON i.order_id = o.id
               WHERE i.product_id = 1986295);

-- -----------------------------------------------------------------------------
-- Q2. Q2 rewritten with a grouped LEFT JOIN
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT u.id, u.username,
       coalesce(s.orders, 0) AS orders,
       s.last_order
FROM users u
LEFT JOIN (
  SELECT user_id, count(*) AS orders, max(created_at) AS last_order
  FROM orders
  WHERE user_id BETWEEN 3000000 AND 3020000
  GROUP BY user_id
) s ON s.user_id = u.id
WHERE u.id BETWEEN 3000000 AND 3020000;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT u.id, u.username,
       coalesce(s.orders, 0) AS orders,
       s.last_order
FROM users u
LEFT JOIN (
  SELECT user_id, count(*) AS orders, max(created_at) AS last_order
  FROM orders
  WHERE user_id BETWEEN 3000000 AND 3020000
  GROUP BY user_id
) s ON s.user_id = u.id
WHERE u.id BETWEEN 3000000 AND 3020000;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT u.id, u.username,
       coalesce(s.orders, 0) AS orders,
       s.last_order
FROM users u
LEFT JOIN (
  SELECT user_id, count(*) AS orders, max(created_at) AS last_order
  FROM orders
  WHERE user_id BETWEEN 3000000 AND 3020000
  GROUP BY user_id
) s ON s.user_id = u.id
WHERE u.id BETWEEN 3000000 AND 3020000;

-- Observe:
--   * One scan of the users' orders + one aggregation; no SubPlan with loops=N

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
