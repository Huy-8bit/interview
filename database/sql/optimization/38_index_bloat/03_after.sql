-- =============================================================================
-- Lab 38 · Index bloat: pgstatindex and REINDEX — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Count a range of transaction ids through the index
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM lab_index_bloat
WHERE transaction_id >= '40000000-0000-0000-0000-000000000000'
  AND transaction_id <  '80000000-0000-0000-0000-000000000000';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM lab_index_bloat
WHERE transaction_id >= '40000000-0000-0000-0000-000000000000'
  AND transaction_id <  '80000000-0000-0000-0000-000000000000';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM lab_index_bloat
WHERE transaction_id >= '40000000-0000-0000-0000-000000000000'
  AND transaction_id <  '80000000-0000-0000-0000-000000000000';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM lab_index_bloat
WHERE transaction_id >= '40000000-0000-0000-0000-000000000000'
  AND transaction_id <  '80000000-0000-0000-0000-000000000000';

-- Observe:
--   * Index Only Scan: Buffers ~ number of index leaf pages in the range
--   * With avg_leaf_density ~20%, five times more pages than necessary

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
