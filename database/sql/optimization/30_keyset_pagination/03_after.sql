-- =============================================================================
-- Lab 30 · Keyset (seek) pagination — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Deep page with OFFSET (for contrast)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 50 OFFSET 1000000;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 50 OFFSET 1000000;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 50 OFFSET 1000000;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, status, total_amount, created_at
FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 50 OFFSET 1000000;

-- Observe:
--   * Incremental Sort (Presorted Key: created_at) over 1,000,050 rows

-- -----------------------------------------------------------------------------
-- Q2. Next page after a cursor (keyset)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE (created_at, id) < ('2026-03-01 00:00:00+00', 1500000)
ORDER BY created_at DESC, id DESC
LIMIT 50;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE (created_at, id) < ('2026-03-01 00:00:00+00', 1500000)
ORDER BY created_at DESC, id DESC
LIMIT 50;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE (created_at, id) < ('2026-03-01 00:00:00+00', 1500000)
ORDER BY created_at DESC, id DESC
LIMIT 50;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, status, total_amount, created_at
FROM orders
WHERE (created_at, id) < ('2026-03-01 00:00:00+00', 1500000)
ORDER BY created_at DESC, id DESC
LIMIT 50;

-- Observe:
--   * Index Cond: (created_at <= ...) + Filter: ROW(created_at, id) < ROW(...)
--   * + Incremental Sort for the id tie-breaker: fast, but not a pure index range

-- -----------------------------------------------------------------------------
-- Q3. Keyset on the primary key
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, total_amount
FROM orders
WHERE id > 4000000
ORDER BY id
LIMIT 50;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, total_amount
FROM orders
WHERE id > 4000000
ORDER BY id
LIMIT 50;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, total_amount
FROM orders
WHERE id > 4000000
ORDER BY id
LIMIT 50;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, total_amount
FROM orders
WHERE id > 4000000
ORDER BY id
LIMIT 50;

-- Observe:
--   * Index Scan using pk_orders, Index Cond: (id > 4000000): reads exactly 50 entries

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
