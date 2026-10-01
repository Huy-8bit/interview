-- =============================================================================
-- Lab 27 · Subquery vs JOIN: what the planner rewrites for you — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Customers who bought the best-selling product (IN subquery)
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

-- Observe:
--   * Semi Join (Hash Semi Join / Nested Loop Semi Join): the planner turned IN into a join
--   * that stops at the first match per user

-- -----------------------------------------------------------------------------
-- Q2. Order count and last order per customer (correlated scalar subqueries)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT u.id, u.username,
       (SELECT count(*)          FROM orders o WHERE o.user_id = u.id) AS orders,
       (SELECT max(o.created_at) FROM orders o WHERE o.user_id = u.id) AS last_order
FROM users u
WHERE u.id BETWEEN 3000000 AND 3020000;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT u.id, u.username,
       (SELECT count(*)          FROM orders o WHERE o.user_id = u.id) AS orders,
       (SELECT max(o.created_at) FROM orders o WHERE o.user_id = u.id) AS last_order
FROM users u
WHERE u.id BETWEEN 3000000 AND 3020000;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT u.id, u.username,
       (SELECT count(*)          FROM orders o WHERE o.user_id = u.id) AS orders,
       (SELECT max(o.created_at) FROM orders o WHERE o.user_id = u.id) AS last_order
FROM users u
WHERE u.id BETWEEN 3000000 AND 3020000;

-- Observe:
--   * SubPlan 1 and SubPlan 2 with loops = number of users: each runs once PER ROW
--   * Scalar subqueries in the SELECT list are NOT flattened into joins

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
