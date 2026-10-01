-- =============================================================================
-- Lab 23 · GROUP BY: HashAggregate vs GroupAggregate — OPTIMIZE · Strategy A
-- Strategy A: (experiment) work_mem = 256MB
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- With more memory the 2.2M-group hash table fits: Batches: 1, no Disk Usage.

-- -----------------------------------------------------------------------------
-- Q2 with work_mem = 256MB
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET work_mem = '256MB';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT user_id, count(*) AS orders, sum(total_amount) AS spent
FROM orders
GROUP BY user_id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT user_id, count(*) AS orders, sum(total_amount) AS spent
FROM orders
GROUP BY user_id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT user_id, count(*) AS orders, sum(total_amount) AS spent
FROM orders
GROUP BY user_id;

RESET work_mem;

-- Observe:
--   * Batches: 1  Memory Usage: N kB

-- Undo only this strategy:
-- RESET work_mem;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
