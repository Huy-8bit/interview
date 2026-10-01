-- =============================================================================
-- Lab 31 · Query rewrites: count > 0, HAVING, UNION, SELECT * — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. 'Are there pending orders?' written with count(*)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT (SELECT count(*) FROM orders WHERE status = 'PENDING') > 0 AS has_pending;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT (SELECT count(*) FROM orders WHERE status = 'PENDING') > 0 AS has_pending;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT (SELECT count(*) FROM orders WHERE status = 'PENDING') > 0 AS has_pending;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT (SELECT count(*) FROM orders WHERE status = 'PENDING') > 0 AS has_pending;

-- Observe:
--   * counts EVERY pending order (index scan over ~5% of the table) to answer yes/no

-- -----------------------------------------------------------------------------
-- Q2. Filter on a GROUP BY column written in HAVING
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT status, count(*)
FROM orders
GROUP BY status
HAVING status IN ('PENDING', 'CONFIRMED');

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT status, count(*)
FROM orders
GROUP BY status
HAVING status IN ('PENDING', 'CONFIRMED');

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT status, count(*)
FROM orders
GROUP BY status
HAVING status IN ('PENDING', 'CONFIRMED');

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT status, count(*)
FROM orders
GROUP BY status
HAVING status IN ('PENDING', 'CONFIRMED');

-- Observe:
--   * Look where the condition ends up: the planner moves HAVING conditions without
--   * aggregates down to the scan (Index Cond / Filter on orders)

-- -----------------------------------------------------------------------------
-- Q3. UNION (removes duplicates) of buyers and reviewers of the last day
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT user_id FROM orders  WHERE created_at >= '2026-09-30'
UNION
SELECT user_id FROM reviews WHERE created_at >= '2026-09-30';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT user_id FROM orders  WHERE created_at >= '2026-09-30'
UNION
SELECT user_id FROM reviews WHERE created_at >= '2026-09-30';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT user_id FROM orders  WHERE created_at >= '2026-09-30'
UNION
SELECT user_id FROM reviews WHERE created_at >= '2026-09-30';

-- Observe:
--   * HashAggregate / Unique on top of Append: the de-duplication step

-- -----------------------------------------------------------------------------
-- Q4. SELECT * of the last day's orders sorted by amount
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT *
FROM orders
WHERE created_at >= '2026-09-30'
ORDER BY total_amount DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT *
FROM orders
WHERE created_at >= '2026-09-30'
ORDER BY total_amount DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT *
FROM orders
WHERE created_at >= '2026-09-30'
ORDER BY total_amount DESC;

-- Observe:
--   * Sort Method: ... Memory: N kB -> the sort carries every column (shipping_address jsonb...)

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
