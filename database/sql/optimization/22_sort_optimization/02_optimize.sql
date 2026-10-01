-- =============================================================================
-- Lab 22 · Sort: in-memory quicksort vs external merge vs no sort — OPTIMIZE · Strategy A
-- Strategy A: (experiment) work_mem = 512MB for this session
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- work_mem is the memory per sort / hash NODE, per query, per process. With
-- enough of it the sort runs in memory (quicksort). Raising it globally is
-- dangerous (100 connections x several nodes x 512MB); raise it per session
-- or per transaction (SET LOCAL) for the queries that need it.

-- -----------------------------------------------------------------------------
-- Q1 with work_mem = 512MB
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET work_mem = '512MB';

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

RESET work_mem;

-- Observe:
--   * Sort Method: quicksort  Memory: N kB

-- Undo only this strategy:
-- RESET work_mem;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
