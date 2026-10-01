-- =============================================================================
-- Lab 35 · Stale statistics and ANALYZE — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Lab table: 1M OLD orders (2023-2025), autovacuum/auto-analyze disabled ON THIS TABLE ONLY,
-- analyzed once, then 400k NEW orders (September 2026) are added WITHOUT ANALYZE:
-- the statistics still describe the old data. Re-created every time this file runs.
DROP TABLE IF EXISTS lab_stale;
CREATE TABLE lab_stale WITH (autovacuum_enabled = false) AS
SELECT id, user_id, status, total_amount, created_at FROM orders WHERE id <= 1000000;
ALTER TABLE lab_stale ADD PRIMARY KEY (id);
CREATE INDEX ix_lab35_stale_created ON lab_stale (created_at);
CREATE INDEX ix_lab35_stale_user ON lab_stale (user_id);
ANALYZE lab_stale;

INSERT INTO lab_stale
SELECT id, user_id, status, total_amount, created_at
FROM orders WHERE created_at >= '2026-09-15' AND id > 1000000
LIMIT 400000;

-- What the planner believes vs reality
SELECT reltuples::bigint AS planner_rows, (SELECT count(*) FROM lab_stale) AS real_rows
FROM pg_class WHERE relname = 'lab_stale';
SELECT n_mod_since_analyze, last_analyze, last_autoanalyze FROM pg_stat_user_tables WHERE relname = 'lab_stale';

-- -----------------------------------------------------------------------------
-- Q1. Recent orders: the histogram does not know they exist
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_stale
WHERE created_at >= '2026-09-15';

-- Observe:
--   * rows= estimate (tiny) vs actual rows (400k): created_at is beyond the histogram's
--   * last bucket, so the planner thinks almost nothing matches

-- -----------------------------------------------------------------------------
-- Q2. The bad estimate drives the join strategy
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT u.status, count(*)
FROM lab_stale s
JOIN users u ON u.id = s.user_id
WHERE s.created_at >= '2026-09-15'
GROUP BY u.status;

-- Observe:
--   * Nested Loop with loops = 400k index lookups into users, chosen because the outer side
--   * was estimated at a handful of rows

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
