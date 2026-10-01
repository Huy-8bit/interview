-- =============================================================================
-- Lab 02 · Selectivity: the same index, different plans — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
-- Value distribution of payments.status (deliberately skewed by the generator)
SELECT status, count(*), round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM payments GROUP BY status ORDER BY count(*) DESC;
-- What the planner believes (statistics gathered by ANALYZE)
SELECT most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'payments' AND attname = 'status';

-- -----------------------------------------------------------------------------
-- Q1. Very common value: SUCCEEDED (~79% of rows)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'SUCCEEDED';

-- Observe:
--   * Seq Scan before AND after the index: reading 79% of the rows through an index
--   * would mean random heap access for almost every page

-- -----------------------------------------------------------------------------
-- Q2. Less common value: PENDING (~8.5%)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'PENDING';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'PENDING';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'PENDING';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'PENDING';

-- Observe:
--   * Before: Seq Scan. After strategy A: an index-based scan.
--   * rows= estimate on the scan node vs the frequency in pg_stats.most_common_freqs

-- -----------------------------------------------------------------------------
-- Q3. Rare value: REFUNDED (~5%)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'REFUNDED';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'REFUNDED';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'REFUNDED';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(amount)
FROM payments
WHERE status = 'REFUNDED';

-- Observe:
--   * Same index, same query shape: the plan depends only on the estimated selectivity

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
