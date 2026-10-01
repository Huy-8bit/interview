-- =============================================================================
-- Lab 01 · Seq Scan vs Index Scan — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Find a user by phone number (1 row out of 5,000,000)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE phone = '+1-236-702-0729';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE phone = '+1-236-702-0729';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE phone = '+1-236-702-0729';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE phone = '+1-236-702-0729';

-- Observe:
--   * Node: (Parallel) Seq Scan on users -> every heap page is read
--   * Rows Removed by Filter: ~ all rows of the table (per worker: x loops)
--   * Buffers: shared hit + read ~ number of heap pages (see the context query above)
--   * Execution Time: dominated by reading the whole table (first run: read=..., later: hit=...)

-- -----------------------------------------------------------------------------
-- Q2. Count users that HAVE a phone (~85% of the table)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users
WHERE phone IS NOT NULL;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users
WHERE phone IS NOT NULL;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users
WHERE phone IS NOT NULL;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users
WHERE phone IS NOT NULL;

-- Observe:
--   * Before: Seq Scan over the whole heap.
--   * After the index exists it can become a (Parallel) Index Only Scan - still a FULL scan,
--   * just of the smaller index (all 85% of the entries are read). An index cannot avoid
--   * visiting most rows when most rows match; it can only make each visit cheaper.

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
