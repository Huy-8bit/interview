-- =============================================================================
-- Lab 20 · Large join: a 5-table revenue report — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

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

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
