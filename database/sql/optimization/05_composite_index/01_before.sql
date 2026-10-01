-- =============================================================================
-- Lab 05 · Composite index: filter + sort in one index — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
-- Category 37 = Snacks: ~281k products, mostly CHEAP. Existing indexes: (category_id) and (price).
SELECT status, count(*) FROM products WHERE category_id = 37 GROUP BY status ORDER BY 2 DESC;
SELECT indexname, indexdef FROM pg_indexes WHERE tablename IN ('products', 'orders') ORDER BY 1;

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
