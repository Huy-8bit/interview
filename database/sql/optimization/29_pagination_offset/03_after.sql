-- =============================================================================
-- Lab 29 · Pagination with OFFSET: the cost of deep pages — AFTER
-- Deferred-join versions of the three pages (fast with strategy B's index).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Page 1 (deferred join)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 0) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 0) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 0) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 0) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- -----------------------------------------------------------------------------
-- Q2. Page 2,001 (deferred join)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 100000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 100000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 100000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.order_number, o.status, o.total_amount, o.created_at
FROM orders o
JOIN (SELECT id FROM orders ORDER BY created_at DESC LIMIT 50 OFFSET 100000) page ON page.id = o.id
ORDER BY o.created_at DESC;

-- -----------------------------------------------------------------------------
-- Q3. Page 20,001 (deferred join)
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
--   * Index Only Scan ... Heap Fetches: 0 in the subquery (with strategy B)

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
