-- =============================================================================
-- Lab 16 · Nested Loop: small outer side + indexed inner lookups — OPTIMIZE · Strategy A
-- Strategy A: (experiment) SET enable_nestloop = off: what would the alternative cost?
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Not an optimization: it shows WHY the planner chose a Nested Loop. Without
-- it, the planner must hash or merge-join the inner tables, which means
-- reading far more of order_items / products than the ~50 rows needed.

-- -----------------------------------------------------------------------------
-- Same query with nested loops disabled
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET enable_nestloop = off;

-- 1) The query itself
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 2215979
ORDER BY o.created_at;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 2215979
ORDER BY o.created_at;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 2215979
ORDER BY o.created_at;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id = 2215979
ORDER BY o.created_at;

RESET enable_nestloop;

-- Observe:
--   * Hash Join / Merge Join + Seq Scans: Buffers and time explode

-- Undo only this strategy:
-- RESET enable_nestloop;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
