-- =============================================================================
-- Lab 06 · Column order in a composite index: equality vs range — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT rating, count(*) FROM reviews GROUP BY rating ORDER BY rating;
SELECT count(*) AS reviews_since_2026_09_01 FROM reviews WHERE created_at >= '2026-09-01';

-- -----------------------------------------------------------------------------
-- Q1. Equality on rating + range on created_at
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM reviews
WHERE rating = 1
  AND created_at >= '2026-09-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM reviews
WHERE rating = 1
  AND created_at >= '2026-09-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM reviews
WHERE rating = 1
  AND created_at >= '2026-09-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM reviews
WHERE rating = 1
  AND created_at >= '2026-09-01';

-- Observe:
--   * Index Cond: which columns are used to DESCEND into the index, which are only checked?
--   * Buffers of the index scan: how much of the index is read?

-- -----------------------------------------------------------------------------
-- Q2. Range on created_at only
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM reviews
WHERE created_at >= '2026-09-25';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM reviews
WHERE created_at >= '2026-09-25';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM reviews
WHERE created_at >= '2026-09-25';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM reviews
WHERE created_at >= '2026-09-25';

-- Observe:
--   * Can an index whose FIRST column is rating help a condition on created_at alone?

-- -----------------------------------------------------------------------------
-- Q3. Equality on rating only
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM reviews
WHERE rating = 2;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM reviews
WHERE rating = 2;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM reviews
WHERE rating = 2;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM reviews
WHERE rating = 2;

-- Observe:
--   * Leftmost prefix: (rating, ...) serves this; (created_at, rating) cannot seek on rating

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
