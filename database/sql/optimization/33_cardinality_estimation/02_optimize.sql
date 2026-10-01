-- =============================================================================
-- Lab 33 · Cardinality estimation: correlated columns and CREATE STATISTICS — OPTIMIZE · Strategy A
-- Strategy A: CREATE STATISTICS (dependencies) ON country_code, city
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Functional dependency statistics record that city determines country_code
-- (degree ~1.0). The planner then stops multiplying the two selectivities.

CREATE STATISTICS st_lab33_addr_country_city (dependencies) ON country_code, city FROM addresses;
ANALYZE addresses;

-- Check what was created / changed:
SELECT statistics_name, attnames, kinds, dependencies, n_distinct
FROM pg_stats_ext WHERE tablename = 'addresses';

-- Undo only this strategy:
-- DROP STATISTICS IF EXISTS st_lab33_addr_country_city;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
