-- =============================================================================
-- Lab 20 · Large join: a 5-table revenue report — OPTIMIZE · Strategy A
-- Strategy A: Rewrite: aggregate order lines per product BEFORE joining products
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- The report only needs revenue per product, then per category. Grouping the
-- order lines by product_id first shrinks the input of the expensive products
-- join from one row per order line to one row per distinct product.

-- -----------------------------------------------------------------------------
-- Pre-aggregated version
-- -----------------------------------------------------------------------------

-- 1) The query itself
WITH per_product AS (
  SELECT i.product_id, count(*) AS lines, sum(i.total_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.id
  WHERE o.status = 'COMPLETED'
    AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
  GROUP BY i.product_id
)
SELECT parent.name AS top_category, sum(pp.lines) AS order_lines, sum(pp.revenue) AS revenue
FROM per_product pp
JOIN products p        ON p.id = pp.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
GROUP BY parent.name
ORDER BY revenue DESC;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
WITH per_product AS (
  SELECT i.product_id, count(*) AS lines, sum(i.total_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.id
  WHERE o.status = 'COMPLETED'
    AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
  GROUP BY i.product_id
)
SELECT parent.name AS top_category, sum(pp.lines) AS order_lines, sum(pp.revenue) AS revenue
FROM per_product pp
JOIN products p        ON p.id = pp.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
GROUP BY parent.name
ORDER BY revenue DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
WITH per_product AS (
  SELECT i.product_id, count(*) AS lines, sum(i.total_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.id
  WHERE o.status = 'COMPLETED'
    AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
  GROUP BY i.product_id
)
SELECT parent.name AS top_category, sum(pp.lines) AS order_lines, sum(pp.revenue) AS revenue
FROM per_product pp
JOIN products p        ON p.id = pp.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
GROUP BY parent.name
ORDER BY revenue DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
WITH per_product AS (
  SELECT i.product_id, count(*) AS lines, sum(i.total_price) AS revenue
  FROM orders o
  JOIN order_items i ON i.order_id = o.id
  WHERE o.status = 'COMPLETED'
    AND o.created_at >= '2026-01-01' AND o.created_at < '2026-07-01'
  GROUP BY i.product_id
)
SELECT parent.name AS top_category, sum(pp.lines) AS order_lines, sum(pp.revenue) AS revenue
FROM per_product pp
JOIN products p        ON p.id = pp.product_id
JOIN categories c      ON c.id = p.category_id
JOIN categories parent ON parent.id = c.parent_id
GROUP BY parent.name
ORDER BY revenue DESC;

-- Observe:
--   * Rows entering the products join: before vs after
--   * Same result as the baseline (compare the output)

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
