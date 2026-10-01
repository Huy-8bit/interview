-- =============================================================================
-- Lab 22 · Sort: in-memory quicksort vs external merge vs no sort — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SHOW work_mem;

-- -----------------------------------------------------------------------------
-- Q1. All 5M orders by amount (result not fetched to the client)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, user_id, total_amount
FROM orders
ORDER BY total_amount DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, user_id, total_amount
FROM orders
ORDER BY total_amount DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, user_id, total_amount
FROM orders
ORDER BY total_amount DESC;

-- Observe:
--   * Sort Method: external merge  Disk: N kB  -> the sort did not fit in work_mem
--   * (EXPLAIN ANALYZE executes the sort but discards the rows: no client transfer)

-- -----------------------------------------------------------------------------
-- Q2. Top 100 orders by amount
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, user_id, total_amount
    FROM orders
    ORDER BY total_amount DESC
LIMIT 100;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, user_id, total_amount
    FROM orders
    ORDER BY total_amount DESC
LIMIT 100;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, user_id, total_amount
    FROM orders
    ORDER BY total_amount DESC
LIMIT 100;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, user_id, total_amount
    FROM orders
    ORDER BY total_amount DESC
LIMIT 100;

-- Observe:
--   * Sort Method: top-N heapsort  Memory: ~kB -> bounded sort, whatever the table size

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
