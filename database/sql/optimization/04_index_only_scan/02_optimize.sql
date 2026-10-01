-- =============================================================================
-- Lab 04 · Index Only Scan, visibility map, Heap Fetches — OPTIMIZE · Strategy A
-- Strategy A: VACUUM: fill the visibility map
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- VACUUM marks pages whose rows are visible to every transaction as
-- all-visible. An Index Only Scan then skips the heap for those pages:
-- Heap Fetches drops to 0. Nothing about the index changes.

VACUUM (ANALYZE) lab_ios;

-- Check what was created / changed:
SELECT relname, relpages, relallvisible FROM pg_class WHERE relname = 'lab_ios';

-- Undo only this strategy:
-- -- (strategy A has no object of its own: 05_reset.sql drops lab_ios)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
