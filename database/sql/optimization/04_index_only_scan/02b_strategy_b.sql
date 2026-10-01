-- =============================================================================
-- Lab 04 · Index Only Scan, visibility map, Heap Fetches — OPTIMIZE · Strategy B
-- Strategy B: Covering index INCLUDE (total_amount) + VACUUM
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Query 2 cannot be index-only because total_amount is not in the index.
-- INCLUDE stores it in the leaf pages (not in the search key), so both
-- queries become Index Only Scans.

CREATE INDEX ix_lab04_ios_created_incl ON lab_ios (created_at) INCLUDE (total_amount);
VACUUM (ANALYZE) lab_ios;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'lab_ios' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab04_ios_created_incl;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
