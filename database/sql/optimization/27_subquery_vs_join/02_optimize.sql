-- =============================================================================
-- Lab 27 · Subquery vs JOIN: what the planner rewrites for you — OPTIMIZE · Strategy A
-- Strategy A: Q1 as JOIN + DISTINCT (the 'manual' rewrite)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- A frequent 'optimization' is to replace IN by a JOIN. The JOIN produces one row
-- per purchase, so DISTINCT is needed to keep the meaning: extra work the semi
-- join avoids. Compare the plans - the original IN was already a join.

-- -----------------------------------------------------------------------------
-- Q1 as JOIN + DISTINCT
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(DISTINCT u.id)
FROM users u
JOIN orders o      ON o.user_id = u.id
JOIN order_items i ON i.order_id = o.id
WHERE i.product_id = 4905450;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(DISTINCT u.id)
FROM users u
JOIN orders o      ON o.user_id = u.id
JOIN order_items i ON i.order_id = o.id
WHERE i.product_id = 4905450;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(DISTINCT u.id)
FROM users u
JOIN orders o      ON o.user_id = u.id
JOIN order_items i ON i.order_id = o.id
WHERE i.product_id = 4905450;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(DISTINCT u.id)
FROM users u
JOIN orders o      ON o.user_id = u.id
JOIN order_items i ON i.order_id = o.id
WHERE i.product_id = 4905450;

-- Observe:
--   * Inner joins + an aggregate that de-duplicates

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
