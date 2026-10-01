-- =============================================================================
-- Lab 33 · Cardinality estimation: correlated columns and CREATE STATISTICS — OPTIMIZE · Strategy B
-- Strategy B: CREATE STATISTICS (mcv) ON country_code, city
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- A multi-column MCV list stores the most common (country_code, city) PAIRS and
-- their frequencies: exact for frequent combinations, also handles inequality and
-- IN lists better than dependencies.

CREATE STATISTICS st_lab33_addr_country_city_mcv (mcv) ON country_code, city FROM addresses;
ANALYZE addresses;

-- Check what was created / changed:
SELECT m.values, round(m.frequency::numeric, 4) AS frequency
FROM pg_statistic_ext s
JOIN pg_statistic_ext_data d ON d.stxoid = s.oid
CROSS JOIN LATERAL pg_mcv_list_items(d.stxdmcv) m
WHERE s.stxname = 'st_lab33_addr_country_city_mcv'
ORDER BY m.frequency DESC LIMIT 10;

-- Undo only this strategy:
-- DROP STATISTICS IF EXISTS st_lab33_addr_country_city_mcv;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
