-- =============================================================================
-- Lab 37 · Table bloat: VACUUM FULL vs CLUSTER — OPTIMIZE · Strategy B
-- Strategy B: CLUSTER ... USING ix_lab37_bloat_user: compact AND physically ordered by user_id
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- CLUSTER also rewrites the table compactly (same lock as VACUUM FULL), but in the
-- order of an index: the orders of one user become adjacent, so Q2 reads far fewer
-- pages (pg_stats.correlation of user_id -> ~1). The order is NOT maintained for
-- future writes: CLUSTER is a one-off operation.

CLUSTER lab_bloat USING ix_lab37_bloat_user;
ANALYZE lab_bloat;

-- Check what was created / changed:
SELECT tuple_count, round(free_percent::numeric, 1) AS free_pct, pg_size_pretty(table_len) AS table_size
FROM pgstattuple('lab_bloat');
SELECT attname, round(correlation::numeric, 3) AS correlation FROM pg_stats WHERE tablename = 'lab_bloat' AND attname = 'user_id';

-- Undo only this strategy:
-- -- (no object of its own: 05_reset.sql drops lab_bloat)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
