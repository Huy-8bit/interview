-- =============================================================================
-- Lab 36 · VACUUM: dead tuples, visibility map, VACUUM vs VACUUM FULL — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Lab table: 1M orders, vacuumed (visibility map set), then 40% of the rows are UPDATEd:
-- every update leaves a dead row version behind and clears the page's all-visible bit.
-- Autovacuum is disabled ON THIS TABLE ONLY so the dead tuples stay for the lab.
DROP TABLE IF EXISTS lab_vacuum;
CREATE TABLE lab_vacuum WITH (autovacuum_enabled = false) AS
SELECT id, user_id, status, total_amount, created_at FROM orders WHERE id <= 1000000;
ALTER TABLE lab_vacuum ADD PRIMARY KEY (id);
CREATE INDEX ix_lab36_vacuum_created ON lab_vacuum (created_at);
VACUUM (ANALYZE) lab_vacuum;

UPDATE lab_vacuum SET total_amount = total_amount + 0 WHERE id % 5 < 2;

-- Exact tuple-level picture (pgstattuple reads the whole table)
SELECT tuple_count, dead_tuple_count, round(dead_tuple_percent::numeric, 1) AS dead_pct,
       round(free_percent::numeric, 1) AS free_pct, pg_size_pretty(table_len) AS table_size
FROM pgstattuple('lab_vacuum');
SELECT relpages, relallvisible FROM pg_class WHERE relname = 'lab_vacuum';

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
