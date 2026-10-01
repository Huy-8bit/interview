-- =============================================================================
-- Lab 23 · GROUP BY: HashAggregate vs GroupAggregate — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Few groups: orders per status
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT status, count(*) AS orders, sum(total_amount) AS amount
FROM orders
GROUP BY status;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT status, count(*) AS orders, sum(total_amount) AS amount
FROM orders
GROUP BY status;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT status, count(*) AS orders, sum(total_amount) AS amount
FROM orders
GROUP BY status;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT status, count(*) AS orders, sum(total_amount) AS amount
FROM orders
GROUP BY status;

-- Observe:
--   * (Partial) HashAggregate: 6 groups -> a tiny hash table, one pass over the rows

-- -----------------------------------------------------------------------------
-- Q2. Millions of groups: orders per customer (2.2M groups, not fetched to the client)
-- -----------------------------------------------------------------------------

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

-- Observe:
--   * HashAggregate ... Batches: N  Disk Usage: N kB -> the hash table did not fit in
--   * work_mem x hash_mem_multiplier and was spilled to disk (PG13+)
--   * or: GroupAggregate fed by a Sort / an ordered index

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
