-- =============================================================================
-- Lab 05 · Composite index: filter + sort in one index — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Top 20 most expensive ACTIVE products of one category
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, name, price
FROM products
WHERE category_id = 37
  AND status = 'ACTIVE'
ORDER BY price DESC
LIMIT 20;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, name, price
FROM products
WHERE category_id = 37
  AND status = 'ACTIVE'
ORDER BY price DESC
LIMIT 20;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, name, price
FROM products
WHERE category_id = 37
  AND status = 'ACTIVE'
ORDER BY price DESC
LIMIT 20;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, name, price
FROM products
WHERE category_id = 37
  AND status = 'ACTIVE'
ORDER BY price DESC
LIMIT 20;

-- Observe:
--   * Which index does the planner pick: idx_products_category_id or idx_products_price?
--   * Index Scan Backward on the price index + Filter = walk ALL products from the most
--   * expensive down until 20 cheap snacks are found -> look at Rows Removed by Filter
--   * The estimate (cost of Limit) assumes matching rows are spread evenly along price order

-- -----------------------------------------------------------------------------
-- Q2. The orders of one customer with a given status, newest first
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE user_id = 2215979
  AND status = 'COMPLETED'
ORDER BY created_at DESC;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE user_id = 2215979
  AND status = 'COMPLETED'
ORDER BY created_at DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE user_id = 2215979
  AND status = 'COMPLETED'
ORDER BY created_at DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE user_id = 2215979
  AND status = 'COMPLETED'
ORDER BY created_at DESC;

-- Observe:
--   * Index Scan using idx_orders_user_id + Filter on status + a separate Sort node
--   * Few rows per user (max 16): the gain here is small but visible in the plan shape

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
