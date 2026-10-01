-- =============================================================================
-- Lab 11 · Implicit casts that disable an index — AFTER
-- The same lookups with the value in the column's own type.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. bigint column, bigint literal
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000;

-- Observe:
--   * Index Scan using pk_orders

-- -----------------------------------------------------------------------------
-- Q2. user_id compared as a number
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, total_amount
FROM orders
WHERE user_id = 1144205;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, total_amount
FROM orders
WHERE user_id = 1144205;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, total_amount
FROM orders
WHERE user_id = 1144205;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, total_amount
FROM orders
WHERE user_id = 1144205;

-- Observe:
--   * Index Scan using idx_orders_user_id

-- -----------------------------------------------------------------------------
-- Q3. phone compared with a varchar/text value
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username
FROM users
WHERE phone = '+1-236-702-0729';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username
FROM users
WHERE phone = '+1-236-702-0729';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username
FROM users
WHERE phone = '+1-236-702-0729';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username
FROM users
WHERE phone = '+1-236-702-0729';

-- Observe:
--   * Still a Seq Scan, but now only because phone has no index (Lab 01):
--   * the comparison is on the bare column, so an index WOULD be usable

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
