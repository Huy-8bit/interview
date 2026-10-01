-- =============================================================================
-- Lab 33 · Cardinality estimation: correlated columns and CREATE STATISTICS — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT count(*) AS vn_hanoi FROM addresses WHERE country_code = 'VN' AND city = 'Hanoi';
-- Per-column frequencies the planner multiplies together:
SELECT attname, most_common_vals, most_common_freqs
FROM pg_stats WHERE tablename = 'addresses' AND attname IN ('country_code');

-- -----------------------------------------------------------------------------
-- Q1. Addresses in Hanoi, Vietnam (two correlated columns)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM addresses
WHERE country_code = 'VN'
  AND city = 'Hanoi';

-- Observe:
--   * rows= estimate vs actual: the planner assumes independence,
--   * P(VN and Hanoi) = P(VN) x P(Hanoi), but every Hanoi address IS in VN

-- -----------------------------------------------------------------------------
-- Q2. The estimate feeds a join: orders shipped to default addresses in Hanoi
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(o.total_amount)
FROM addresses a
JOIN orders o ON o.user_id = a.user_id
WHERE a.country_code = 'VN'
  AND a.city = 'Hanoi'
  AND a.is_default;

-- Observe:
--   * The underestimated outer side makes a Nested Loop look cheap: check loops= on the inner node

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
