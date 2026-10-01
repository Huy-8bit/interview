-- =============================================================================
-- Lab 02 · Selectivity: the same index, different plans — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

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

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
