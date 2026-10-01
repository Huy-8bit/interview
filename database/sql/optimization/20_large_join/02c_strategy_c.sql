-- =============================================================================
-- Lab 20 · Large join: a 5-table revenue report — OPTIMIZE · Strategy C
-- Strategy C: (experiment) more parallel workers: max_parallel_workers_per_gather = 4
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- The default allows 2 workers per Gather. More workers split the scans and the
-- partial aggregation further (8 CPUs on the lab machine). Parallelism reduces
-- wall time, not total work: compare the sum of buffers.

-- -----------------------------------------------------------------------------
-- Baseline query with up to 4 workers
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET max_parallel_workers_per_gather = 4;

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

RESET max_parallel_workers_per_gather;

-- Observe:
--   * Workers Planned / Workers Launched

-- Undo only this strategy:
-- RESET max_parallel_workers_per_gather;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
