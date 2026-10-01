-- =============================================================================
-- Lab 01 · Seq Scan vs Index Scan — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT pg_size_pretty(pg_relation_size('users')) AS users_heap,
       (SELECT relpages FROM pg_class WHERE relname = 'users') AS heap_pages_8kb,
       (SELECT to_char(reltuples, 'FM999,999,999') FROM pg_class WHERE relname = 'users') AS est_rows;
-- users.phone has NO index in the baseline:
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
