-- =============================================================================
-- Lab 34 · Extended statistics: ndistinct for multi-column GROUP BY — OPTIMIZE · Strategy B
-- Strategy B: All kinds at once: (ndistinct, dependencies, mcv) on country_code, state, city
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Real address data has a hierarchy (country > state > city). One statistics object
-- can carry every kind for up to 8 columns; ANALYZE cost and pg_statistic_ext size
-- grow with the number of columns and kinds.

CREATE STATISTICS st_lab34_addr_all (ndistinct, dependencies, mcv) ON country_code, state, city FROM addresses;
ANALYZE addresses;

-- Check what was created / changed:
SELECT statistics_name, attnames, kinds, n_distinct, dependencies FROM pg_stats_ext WHERE tablename = 'addresses';

-- Undo only this strategy:
-- DROP STATISTICS IF EXISTS st_lab34_addr_all;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
