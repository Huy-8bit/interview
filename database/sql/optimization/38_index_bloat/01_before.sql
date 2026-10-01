-- =============================================================================
-- Lab 38 · Index bloat: pgstatindex and REINDEX — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Lab table: 1M payments with an index on a RANDOM uuid key (gen_random_uuid()), then 80% of
-- the rows deleted and vacuumed: the index keeps its pages, now mostly empty.
DROP TABLE IF EXISTS lab_index_bloat;
CREATE TABLE lab_index_bloat AS
SELECT id, order_id, gen_random_uuid() AS transaction_id, amount, created_at FROM payments
WHERE id <= 1000000;   -- random uuid v4 keys (generated here, so the lab does not depend on the data generator)
CREATE INDEX ix_lab38_ibloat_txn ON lab_index_bloat (transaction_id);
DELETE FROM lab_index_bloat WHERE id % 5 <> 0;

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

VACUUM (ANALYZE) lab_index_bloat;

SELECT pg_size_pretty(pg_relation_size('ix_lab38_ibloat_txn')) AS index_size, leaf_pages, empty_pages,
       deleted_pages, avg_leaf_density
FROM pgstatindex('ix_lab38_ibloat_txn');

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
