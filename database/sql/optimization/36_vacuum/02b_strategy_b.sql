-- =============================================================================
-- Lab 36 · VACUUM: dead tuples, visibility map, VACUUM vs VACUUM FULL — OPTIMIZE · Strategy B
-- Strategy B: VACUUM FULL: rewrite the table compactly
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- VACUUM FULL writes a brand new copy of the table and its indexes without the dead
-- space, then swaps the files: the size shrinks. It holds an ACCESS EXCLUSIVE lock
-- for the whole duration (no reads, no writes) and needs disk space for the copy.

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

VACUUM (FULL, VERBOSE, ANALYZE) lab_vacuum;

-- Check what was created / changed:
SELECT tuple_count, dead_tuple_count, round(free_percent::numeric, 1) AS free_pct, pg_size_pretty(table_len) AS table_size
FROM pgstattuple('lab_vacuum');
SELECT relpages, relallvisible FROM pg_class WHERE relname = 'lab_vacuum';

-- Undo only this strategy:
-- -- (no object of its own: 05_reset.sql drops lab_vacuum)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
