-- =============================================================================
-- Lab 40 · Partition pruning: scan only the relevant partitions — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Lab tables (the real orders table is never touched): the 2025-01 .. 2026-09 orders,
-- narrow columns. lab_orders_flat = one ordinary table, NO index on created_at.
-- Re-created every time this file runs.
DROP TABLE IF EXISTS lab_orders_part;
DROP TABLE IF EXISTS lab_orders_flat;
CREATE TABLE lab_orders_flat AS
SELECT id, user_id, status, total_amount, created_at
FROM orders
WHERE created_at >= '2025-01-01' AND created_at < '2026-10-01';
ANALYZE lab_orders_flat;
SELECT count(*) AS rows, pg_size_pretty(pg_relation_size('lab_orders_flat')) AS size FROM lab_orders_flat;

-- -----------------------------------------------------------------------------
-- Revenue of June 2026 on the ordinary table
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_orders_flat
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_orders_flat
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_orders_flat
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_orders_flat
WHERE created_at >= '2026-06-01' AND created_at < '2026-07-01';

-- Observe:
--   * Seq Scan of the whole table (no index on created_at): Rows Removed by Filter

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
