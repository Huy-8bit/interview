-- =============================================================================
-- Lab 34 · Extended statistics: ndistinct for multi-column GROUP BY — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT count(*) AS real_groups FROM (SELECT DISTINCT country_code, city FROM addresses) s;
SELECT attname, n_distinct FROM pg_stats WHERE tablename = 'addresses' AND attname IN ('country_code', 'city');

-- -----------------------------------------------------------------------------
-- Q1. Addresses per (country, city)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT country_code, city, count(*)
FROM addresses
GROUP BY country_code, city;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT country_code, city, count(*)
FROM addresses
GROUP BY country_code, city;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT country_code, city, count(*)
FROM addresses
GROUP BY country_code, city;

-- Observe:
--   * rows= on the aggregate = n_distinct(country_code) x n_distinct(city) (capped):
--   * far more groups than really exist -> oversized hash table estimates

-- -----------------------------------------------------------------------------
-- Q2. The group estimate feeds the next step: cities with more than 1,000 addresses
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT country_code, city, count(*) AS addresses
FROM addresses
GROUP BY country_code, city
HAVING count(*) > 1000
ORDER BY addresses DESC;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT country_code, city, count(*) AS addresses
FROM addresses
GROUP BY country_code, city
HAVING count(*) > 1000
ORDER BY addresses DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT country_code, city, count(*) AS addresses
FROM addresses
GROUP BY country_code, city
HAVING count(*) > 1000
ORDER BY addresses DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT country_code, city, count(*) AS addresses
FROM addresses
GROUP BY country_code, city
HAVING count(*) > 1000
ORDER BY addresses DESC;

-- Observe:
--   * Estimated vs actual rows of the HashAggregate and of the Sort above it

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
