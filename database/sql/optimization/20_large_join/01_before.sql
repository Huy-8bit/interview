-- =============================================================================
-- Lab 20 · Large join: a 5-table revenue report — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT count(*) AS completed_orders_h1_2026 FROM orders
WHERE status = 'COMPLETED' AND created_at >= '2026-01-01' AND created_at < '2026-07-01';
SELECT pg_size_pretty(pg_relation_size('products')) AS products_heap,
       (SELECT avg(pg_column_size(p.*))::int FROM (SELECT * FROM products LIMIT 1000) p) AS avg_row_bytes;

-- -----------------------------------------------------------------------------
-- Revenue per top-level category, completed orders of H1 2026
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT parent.name        AS top_category,
       count(*)           AS order_lines,
       sum(i.total_price) AS revenue
FROM orders o
JOIN order_items i     ON i.order_id = o.id
JOIN products p        ON p.id = i.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
WHERE o.status = 'COMPLETED'
  AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
GROUP BY parent.name
ORDER BY revenue DESC;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT parent.name        AS top_category,
       count(*)           AS order_lines,
       sum(i.total_price) AS revenue
FROM orders o
JOIN order_items i     ON i.order_id = o.id
JOIN products p        ON p.id = i.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
WHERE o.status = 'COMPLETED'
  AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
GROUP BY parent.name
ORDER BY revenue DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT parent.name        AS top_category,
       count(*)           AS order_lines,
       sum(i.total_price) AS revenue
FROM orders o
JOIN order_items i     ON i.order_id = o.id
JOIN products p        ON p.id = i.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
WHERE o.status = 'COMPLETED'
  AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
GROUP BY parent.name
ORDER BY revenue DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT parent.name        AS top_category,
       count(*)           AS order_lines,
       sum(i.total_price) AS revenue
FROM orders o
JOIN order_items i     ON i.order_id = o.id
JOIN products p        ON p.id = i.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
WHERE o.status = 'COMPLETED'
  AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
GROUP BY parent.name
ORDER BY revenue DESC;

-- Observe:
--   * Read the tree bottom-up: which table drives the join, how many rows flow upward
--   * The products lookup: Hash Join over a Seq Scan of a 2 GB table, or Nested Loop +
--   * Memoize over pk_products? (Memoize: Hits / Misses / Evictions)
--   * Buffers: how much of the total comes from products?

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
