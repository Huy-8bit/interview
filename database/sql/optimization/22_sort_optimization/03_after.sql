-- =============================================================================
-- Lab 22 · Sort: in-memory quicksort vs external merge vs no sort — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

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

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
