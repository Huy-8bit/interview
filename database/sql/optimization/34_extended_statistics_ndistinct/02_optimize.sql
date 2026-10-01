-- =============================================================================
-- Lab 34 · Extended statistics: ndistinct for multi-column GROUP BY — OPTIMIZE · Strategy A
-- Strategy A: CREATE STATISTICS (ndistinct) ON country_code, city
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Stores the number of distinct COMBINATIONS of the columns, measured on the
-- ANALYZE sample, so GROUP BY estimates no longer multiply per-column counts.

CREATE STATISTICS st_lab34_addr_ndistinct (ndistinct) ON country_code, city FROM addresses;
ANALYZE addresses;

-- Check what was created / changed:
SELECT statistics_name, attnames, n_distinct FROM pg_stats_ext WHERE tablename = 'addresses';

-- Undo only this strategy:
-- DROP STATISTICS IF EXISTS st_lab34_addr_ndistinct;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
