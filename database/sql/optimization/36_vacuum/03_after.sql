-- =============================================================================
-- Lab 36 · VACUUM: dead tuples, visibility map, VACUUM vs VACUUM FULL — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Count a date range through the index (wants an Index Only Scan)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM lab_vacuum
WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM lab_vacuum
WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM lab_vacuum
WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM lab_vacuum
WHERE created_at >= '2025-01-01' AND created_at < '2025-04-01';

-- Observe:
--   * Heap Fetches: pages touched by the UPDATE are no longer all-visible
--   * (and every updated row has TWO index entries pointing at two versions)

-- -----------------------------------------------------------------------------
-- Q2. Full scan: dead tuples are read too
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_vacuum;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_vacuum;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_vacuum;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_vacuum;

-- Observe:
--   * Buffers of the Seq Scan = all pages, including the space taken by dead versions

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
