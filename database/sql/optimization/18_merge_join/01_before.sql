-- =============================================================================
-- Lab 18 · Merge Join: two inputs already sorted on the join key — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Every order with its payments, in order id order (5M+ rows - not fetched to the client)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.status, p.status AS payment_status, p.amount
FROM orders o
JOIN payments p ON p.order_id = o.id
ORDER BY o.id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.status, p.status AS payment_status, p.amount
FROM orders o
JOIN payments p ON p.order_id = o.id
ORDER BY o.id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.status, p.status AS payment_status, p.amount
FROM orders o
JOIN payments p ON p.order_id = o.id
ORDER BY o.id;

-- Observe:
--   * Merge Join with Merge Cond: (o.id = p.order_id)
--   * Both inputs come from indexes (pk_orders, idx_payments_order_id): already sorted,
--   * no Sort node. The output is sorted too -> the ORDER BY costs nothing extra

-- -----------------------------------------------------------------------------
-- Q2. First 100,000 order lines in order id order
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.created_at, i.product_id, i.quantity
FROM orders o
JOIN order_items i ON i.order_id = o.id
ORDER BY o.id
LIMIT 100000;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.created_at, i.product_id, i.quantity
FROM orders o
JOIN order_items i ON i.order_id = o.id
ORDER BY o.id
LIMIT 100000;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.created_at, i.product_id, i.quantity
FROM orders o
JOIN order_items i ON i.order_id = o.id
ORDER BY o.id
LIMIT 100000;

-- Observe:
--   * Merge Join under a Limit: it stops as soon as 100,000 rows are produced
--   * (startup cost of a merge join on sorted inputs is ~0)

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
