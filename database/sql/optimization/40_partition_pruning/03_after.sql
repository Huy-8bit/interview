-- =============================================================================
-- Lab 40 · Partition pruning: scan only the relevant partitions — AFTER
-- The same question on the partitioned table, plus runtime pruning and a query without the key.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Revenue of June 2026 on the partitioned table (plan-time pruning)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- Observe:
--   * Only lab_orders_part_2026_06 appears in the plan

-- -----------------------------------------------------------------------------
-- Q2. Last 7 days, bound computed at execution time (runtime pruning)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= (SELECT max(created_at) FROM lab_orders_part_2026_09) - interval '7 days';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= (SELECT max(created_at) FROM lab_orders_part_2026_09) - interval '7 days';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= (SELECT max(created_at) FROM lab_orders_part_2026_09) - interval '7 days';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_orders_part
WHERE created_at >= (SELECT max(created_at) FROM lab_orders_part_2026_09) - interval '7 days';

-- Observe:
--   * Append with 'Subplans Removed: N' (initial pruning) or partitions marked (never executed)

-- -----------------------------------------------------------------------------
-- Q3. A query WITHOUT the partition key scans every partition
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM lab_orders_part
WHERE user_id = 1269637;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM lab_orders_part
WHERE user_id = 1269637;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM lab_orders_part
WHERE user_id = 1269637;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM lab_orders_part
WHERE user_id = 1269637;

-- Observe:
--   * One scan per partition under Append: partitioning only helps queries that filter on the key

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
