-- =============================================================================
-- Lab 37 · Table bloat: VACUUM FULL vs CLUSTER — OPTIMIZE · Strategy A
-- Strategy A: VACUUM FULL: compact rewrite
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Rewrites the table with only live rows: ~70% smaller file, Seq Scans read ~70%
-- fewer pages. ACCESS EXCLUSIVE lock for the whole rewrite.

VACUUM (FULL, ANALYZE) lab_bloat;

-- Check what was created / changed:
SELECT tuple_count, round(free_percent::numeric, 1) AS free_pct, pg_size_pretty(table_len) AS table_size
FROM pgstattuple('lab_bloat');

-- Undo only this strategy:
-- -- (no object of its own: 05_reset.sql drops lab_bloat)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
