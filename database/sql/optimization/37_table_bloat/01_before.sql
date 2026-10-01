-- =============================================================================
-- Lab 37 · Table bloat: VACUUM FULL vs CLUSTER — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Lab table: 1M orders, then 70% of the rows are DELETEd and vacuumed:
-- the file keeps its size, mostly empty pages. Re-created every time this file runs.
DROP TABLE IF EXISTS lab_bloat;
CREATE TABLE lab_bloat AS
SELECT id, user_id, status, total_amount, created_at, shipping_address FROM orders WHERE id <= 1000000;
ALTER TABLE lab_bloat ADD PRIMARY KEY (id);
CREATE INDEX ix_lab37_bloat_user ON lab_bloat (user_id);
DELETE FROM lab_bloat WHERE id % 10 < 7;

-- hot_standby_feedback (on in this lab): the replica reports its oldest snapshot to the
-- primary through the replication slot (pg_replication_slots.xmin) about once per second.
-- Until that report covers the changes made just above, the primary must assume the
-- replica still needs the old row versions, and VACUUM / VACUUM FULL / REINDEX keep them
-- ("dead but not yet removable"). Wait for the report (at most 10 s) so the lab is repeatable.
DO $$
DECLARE
  target bigint := pg_snapshot_xmax(pg_current_snapshot())::text::bigint;   -- next xid, none assigned
BEGIN
  FOR i IN 1..50 LOOP
    EXIT WHEN NOT EXISTS (SELECT 1 FROM pg_replication_slots
                          WHERE xmin IS NOT NULL AND xmin::text::bigint < target);
    PERFORM pg_sleep(0.2);
  END LOOP;
END $$;
SELECT slot_name, xmin AS slot_xmin FROM pg_replication_slots;

VACUUM (ANALYZE) lab_bloat;

SELECT tuple_count, round(tuple_percent::numeric, 1) AS live_pct, round(free_percent::numeric, 1) AS free_pct,
       pg_size_pretty(table_len) AS table_size
FROM pgstattuple('lab_bloat');

-- -----------------------------------------------------------------------------
-- Q1. Full scan of the 30% remaining rows
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), sum(total_amount)
FROM lab_bloat;

-- Observe:
--   * Buffers = all pages of the file, though 70% of their space is empty

-- -----------------------------------------------------------------------------
-- Q2. All orders of a range of users (rows scattered over the table)
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT user_id, count(*), sum(total_amount)
FROM lab_bloat
WHERE user_id BETWEEN 1000000 AND 1100000
GROUP BY user_id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT user_id, count(*), sum(total_amount)
FROM lab_bloat
WHERE user_id BETWEEN 1000000 AND 1100000
GROUP BY user_id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT user_id, count(*), sum(total_amount)
FROM lab_bloat
WHERE user_id BETWEEN 1000000 AND 1100000
GROUP BY user_id;

-- Observe:
--   * Bitmap Heap Scan: Heap Blocks = how many pages hold the matching rows

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
