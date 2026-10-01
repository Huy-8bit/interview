-- =============================================================================
-- Lab 30 · Keyset (seek) pagination — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
-- A 'cursor' = the sort key of the LAST row of the previous page. Example: the row that ends a page
SELECT created_at, id FROM orders WHERE created_at < '2026-03-01' ORDER BY created_at DESC, id DESC LIMIT 1;

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
