-- =============================================================================
-- Lab 35 · Stale statistics and ANALYZE — OPTIMIZE · Strategy A
-- Strategy A: ANALYZE lab_stale
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- ANALYZE re-samples the table: new histogram (now reaching September 2026), new
-- reltuples. Autovacuum normally does this automatically once
-- n_mod_since_analyze > autovacuum_analyze_threshold + scale_factor x reltuples
-- (50 + 10%); it is disabled on this lab table to keep it stale. After bulk loads,
-- run ANALYZE yourself instead of waiting.

ANALYZE lab_stale;

-- Check what was created / changed:
SELECT reltuples::bigint AS planner_rows FROM pg_class WHERE relname = 'lab_stale';
SELECT n_mod_since_analyze, last_analyze FROM pg_stat_user_tables WHERE relname = 'lab_stale';

-- Undo only this strategy:
-- -- (strategy A has no object of its own: 05_reset.sql drops lab_stale)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
