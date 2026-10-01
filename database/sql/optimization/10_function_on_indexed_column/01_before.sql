-- =============================================================================
-- Lab 10 · Function on an indexed column (sargable queries) — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders' AND indexdef LIKE '%created_at%';

-- -----------------------------------------------------------------------------
-- Q1. Orders of one day, written with a cast
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE created_at::date = '2026-06-15';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE created_at::date = '2026-06-15';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE created_at::date = '2026-06-15';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE created_at::date = '2026-06-15';

-- Observe:
--   * The index on created_at is read ENTIRELY (or the table is): the cast is applied
--   * to every row, then compared -> Filter + Rows Removed by Filter

-- -----------------------------------------------------------------------------
-- Q2. Orders of one day, written with date_trunc
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE date_trunc('day', created_at) = '2026-06-15';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE date_trunc('day', created_at) = '2026-06-15';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE date_trunc('day', created_at) = '2026-06-15';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE date_trunc('day', created_at) = '2026-06-15';

-- Observe:
--   * Same problem with any function wrapped around the column

-- -----------------------------------------------------------------------------
-- Q3. Orders of February 2026, written with extract
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE extract(year FROM created_at) = 2026
  AND extract(month FROM created_at) = 2;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE extract(year FROM created_at) = 2026
  AND extract(month FROM created_at) = 2;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE extract(year FROM created_at) = 2026
  AND extract(month FROM created_at) = 2;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE extract(year FROM created_at) = 2026
  AND extract(month FROM created_at) = 2;

-- Observe:
--   * Estimated rows: the planner has no statistics on extract(...) -> default guess

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
