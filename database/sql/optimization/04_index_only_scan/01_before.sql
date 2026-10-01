-- =============================================================================
-- Lab 04 · Index Only Scan, visibility map, Heap Fetches — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Lab table (the main tables are never modified by this lab): 1,000,000 orders.
-- Re-created every time this file runs, WITHOUT a VACUUM: its visibility map is empty.
DROP TABLE IF EXISTS lab_ios;
CREATE TABLE lab_ios AS
SELECT id, user_id, status, total_amount, created_at
FROM orders
WHERE id <= 1000000;
ALTER TABLE lab_ios ADD PRIMARY KEY (id);
CREATE INDEX ix_lab04_ios_created ON lab_ios (created_at);
ANALYZE lab_ios;          -- statistics yes, but ANALYZE does not set the visibility map

-- relallvisible = pages marked all-visible in the visibility map (0 right now)
SELECT relname, relpages, relallvisible FROM pg_class WHERE relname = 'lab_ios';

-- -----------------------------------------------------------------------------
-- Q1. Count orders in a date range: every needed column is in the index
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- Observe:
--   * Index Only Scan using ix_lab04_ios_created ... Heap Fetches: N
--   * Heap Fetches = rows whose visibility had to be checked in the heap because their page
--   * is not all-visible in the visibility map -> right now: (almost) all of them
--   * (the planner may even prefer another plan while relallvisible = 0: note what it picks)

-- -----------------------------------------------------------------------------
-- Q2. Same range, but also reads total_amount (NOT in the index)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT sum(total_amount)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT sum(total_amount)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT sum(total_amount)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT sum(total_amount)
FROM lab_ios
WHERE created_at >= '2025-06-01' AND created_at < '2025-09-01';

-- Observe:
--   * Index Scan / Bitmap Heap Scan: the heap must be read for total_amount anyway

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
