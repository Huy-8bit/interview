-- =============================================================================
-- Lab 16 · Nested Loop: small outer side + indexed inner lookups — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Order history of one customer: orders -> order lines -> products
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 1269637
ORDER BY o.created_at;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 1269637
ORDER BY o.created_at;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 1269637
ORDER BY o.created_at;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 1269637
ORDER BY o.created_at;

-- Observe:
--   * Two nested Nested Loops. Outer: Index Scan on orders (16 rows).
--   * Inner: Index Scan on order_items with loops=16, then pk_products with loops=<lines>
--   * actual rows of an inner node are PER LOOP: total = rows x loops

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
