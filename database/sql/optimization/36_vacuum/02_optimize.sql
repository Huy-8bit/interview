-- =============================================================================
-- Lab 36 · VACUUM: dead tuples, visibility map, VACUUM vs VACUUM FULL — OPTIMIZE · Strategy A
-- Strategy A: VACUUM (VERBOSE): remove dead tuples, set the visibility map
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- VACUUM removes dead row versions (and their index entries), records the freed
-- space in the free space map for future INSERT/UPDATE, and marks clean pages
-- all-visible. It does NOT give the space back to the OS (except empty pages at
-- the very end of the file) and takes only a SHARE UPDATE EXCLUSIVE lock:
-- reads and writes continue.

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

VACUUM (VERBOSE, ANALYZE) lab_vacuum;

-- Check what was created / changed:
SELECT tuple_count, dead_tuple_count, round(free_percent::numeric, 1) AS free_pct, pg_size_pretty(table_len) AS table_size
FROM pgstattuple('lab_vacuum');
SELECT relpages, relallvisible FROM pg_class WHERE relname = 'lab_vacuum';

-- Undo only this strategy:
-- -- (no object of its own: 05_reset.sql drops lab_vacuum)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
