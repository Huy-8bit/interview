-- =============================================================================
-- Lab 14 · OR conditions: BitmapOr, missing index, OR across a join — OPTIMIZE · Strategy B
-- Strategy B: Rewrite the cross-table OR as UNION (each branch uses its own index)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Split the OR into two queries that each filter ONE table through an index,
-- then UNION them (UNION removes duplicates - a row matching both branches
-- must appear once, like with OR). No DDL.

-- -----------------------------------------------------------------------------
-- Q3 rewritten with UNION
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241217-00250000'
UNION
SELECT o.id, o.order_number, u.username
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.username = 'marilyn.johnston4242';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241217-00250000'
UNION
SELECT o.id, o.order_number, u.username
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.username = 'marilyn.johnston4242';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241217-00250000'
UNION
SELECT o.id, o.order_number, u.username
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.username = 'marilyn.johnston4242';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241217-00250000'
UNION
SELECT o.id, o.order_number, u.username
FROM users u
JOIN orders o ON o.user_id = u.id
WHERE u.username = 'marilyn.johnston4242';

-- Observe:
--   * Two small Nested Loops (index lookups) + HashAggregate/Unique for UNION

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
