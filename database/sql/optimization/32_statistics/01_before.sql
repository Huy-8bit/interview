-- =============================================================================
-- Lab 32 · Planner statistics: n_distinct, MCV, histogram, correlation — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT attname, null_frac, n_distinct, array_length(most_common_vals::text::text[], 1) AS n_mcv,
       array_length(histogram_bounds::text::text[], 1) AS n_histogram_bounds, round(correlation::numeric, 3) AS correlation
FROM pg_stats WHERE tablename = 'orders' AND attname IN ('user_id', 'status', 'total_amount', 'created_at')
ORDER BY attname;
    -- Reality to compare with:
    SELECT count(DISTINCT user_id) AS real_distinct_user_ids, count(*) AS rows FROM orders;
    -- Statistics target used by ANALYZE (sample = 300 x target rows)
    SHOW default_statistics_target;

-- -----------------------------------------------------------------------------
-- Q1. GROUP BY user_id: how many groups does the planner expect?
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT user_id, count(*)
FROM orders
GROUP BY user_id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT user_id, count(*)
FROM orders
GROUP BY user_id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT user_id, count(*)
FROM orders
GROUP BY user_id;

-- Observe:
--   * rows= on the aggregate node = the planner's n_distinct estimate; actual rows = real groups
--   * A wrong group count changes memory decisions (HashAggregate vs GroupAggregate, batches)

-- -----------------------------------------------------------------------------
-- Q2. Equality on one user_id: selectivity of a value NOT in the MCV list
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE user_id = 1269637;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE user_id = 1269637;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE user_id = 1269637;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE user_id = 1269637;

-- Observe:
--   * estimated rows ~ (1 - sum(MCV freqs) - null_frac) / (n_distinct - n_MCV) x reltuples

-- -----------------------------------------------------------------------------
-- Q3. Range on total_amount: estimated from the histogram
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE total_amount BETWEEN 100 AND 105;

-- Observe:
--   * Seq Scan rows= comes from the fraction of histogram buckets covering [100, 105]

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
