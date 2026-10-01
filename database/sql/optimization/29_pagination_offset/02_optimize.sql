-- =============================================================================
-- Lab 29 · Pagination with OFFSET: the cost of deep pages — OPTIMIZE · Strategy A
-- Strategy A: (experiment) 'deferred join' WITHOUT a suitable index
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Idea: paginate over a narrow subquery (ids only), then fetch the 50 full rows.
-- But idx_orders_created_at does not contain id: the subquery still visits the
-- heap for every skipped row. Measured on the lab: no gain. A technique only
-- works if the plan underneath supports it.

-- -----------------------------------------------------------------------------
-- Deferred join, OFFSET 1,000,000
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 1000000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 1000000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 1000000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 1000000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- Observe:
--   * Inner Index Scan Backward (not Index Only): heap visited for all skipped rows

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
