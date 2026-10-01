-- =============================================================================
-- Lab 16 · Nested Loop: small outer side + indexed inner lookups — OPTIMIZE · Strategy B
-- Strategy B: (experiment) Grow the outer side: when does the planner leave the Nested Loop?
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- A Nested Loop costs (outer rows) x (one inner lookup). It is ideal for a few
-- outer rows and degrades linearly. The same query for 1, ~1,000 and ~100,000
-- customers shows the planner switching strategy as the outer side grows.

-- -----------------------------------------------------------------------------
-- Q1. ~1,000 customers (user_id range of 2,500)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id BETWEEN 2000000 AND 2002500
ORDER BY o.created_at;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id BETWEEN 2000000 AND 2002500
ORDER BY o.created_at;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id BETWEEN 2000000 AND 2002500
ORDER BY o.created_at;

-- -----------------------------------------------------------------------------
-- Q2. ~100,000 customers (user_id range of 250,000)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id BETWEEN 2000000 AND 2250000
ORDER BY o.created_at;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id BETWEEN 2000000 AND 2250000
ORDER BY o.created_at;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.order_number, o.created_at, p.name AS product, i.quantity, i.total_price
FROM orders o
JOIN order_items i ON i.order_id = o.id
JOIN products p    ON p.id = i.product_id
WHERE o.user_id BETWEEN 2000000 AND 2250000
ORDER BY o.created_at;

-- Observe:
--   * Which join types appear now? Compare loops= and Buffers with Q1

-- Undo only this strategy:
-- -- (nothing to undo: no DDL, no settings)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
