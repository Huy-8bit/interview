-- =============================================================================
-- Lab 10 · Function on an indexed column (sargable queries) — AFTER
-- The same three questions, rewritten as sargable ranges on the bare created_at column.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Orders of one day (range)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE created_at >= '2026-06-15'
  AND created_at <  '2026-06-16';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE created_at >= '2026-06-15'
  AND created_at <  '2026-06-16';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE created_at >= '2026-06-15'
  AND created_at <  '2026-06-16';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE created_at >= '2026-06-15'
  AND created_at <  '2026-06-16';

-- Observe:
--   * Index Cond on created_at: only the entries of that day are read

-- -----------------------------------------------------------------------------
-- Q2. Orders of one day (range, same as Q1)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE created_at >= timestamptz '2026-06-15'
  AND created_at <  timestamptz '2026-06-15' + interval '1 day';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE created_at >= timestamptz '2026-06-15'
  AND created_at <  timestamptz '2026-06-15' + interval '1 day';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE created_at >= timestamptz '2026-06-15'
  AND created_at <  timestamptz '2026-06-15' + interval '1 day';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE created_at >= timestamptz '2026-06-15'
  AND created_at <  timestamptz '2026-06-15' + interval '1 day';

-- -----------------------------------------------------------------------------
-- Q3. Orders of February 2026 (range)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM orders
WHERE created_at >= '2026-02-01'
  AND created_at <  '2026-03-01';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM orders
WHERE created_at >= '2026-02-01'
  AND created_at <  '2026-03-01';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM orders
WHERE created_at >= '2026-02-01'
  AND created_at <  '2026-03-01';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM orders
WHERE created_at >= '2026-02-01'
  AND created_at <  '2026-03-01';

-- Observe:
--   * Estimated rows now come from the created_at histogram: compare with the extract() guess

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
