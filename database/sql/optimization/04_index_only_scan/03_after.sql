-- =============================================================================
-- Lab 04 · Index Only Scan, visibility map, Heap Fetches — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- (Optional experiment, after the queries below) dirty some pages and watch Heap Fetches grow again:
--   UPDATE lab_ios SET status = status WHERE created_at >= '2025-07-01' AND created_at < '2025-07-08';
--   then re-run the EXPLAIN (ANALYZE, BUFFERS) below, then VACUUM lab_ios; and run it once more.
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

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
