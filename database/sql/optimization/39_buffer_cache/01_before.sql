-- =============================================================================
-- Lab 39 · Buffer cache: shared hit vs read, cold vs warm, working set — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

SHOW shared_buffers;

-- Which relations occupy shared_buffers right now (pg_buffercache, 8 KB per buffer)
SELECT c.relname, count(*) AS buffers, pg_size_pretty(count(*) * 8192) AS cached,
       round(100.0 * count(*) / (SELECT setting::int FROM pg_settings WHERE name = 'shared_buffers'), 1) AS pct_of_shared_buffers
FROM pg_buffercache b
JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
               AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 10;

-- -----------------------------------------------------------------------------
-- Revenue of the second half of September (reads ~800k order rows from the heap)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM orders
WHERE created_at >= '2026-09-15';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM orders
WHERE created_at >= '2026-09-15';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM orders
WHERE created_at >= '2026-09-15';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM orders
WHERE created_at >= '2026-09-15';

-- Observe:
--   * Run the file twice. First run: Buffers 'read=' high (pages copied into shared_buffers
--   * from the OS page cache or disk). Second run: more 'hit=' - same plan, same work,
--   * different time. Do not mistake a warm cache for an optimization.
--   * shared_buffers is 256MB: a working set bigger than that keeps being evicted

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
