-- =============================================================================
-- Lab 33 · Cardinality estimation: correlated columns and CREATE STATISTICS — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: CREATE STATISTICS (dependencies) ON country_code, city
DROP STATISTICS IF EXISTS st_lab33_addr_country_city;

-- Reset Strategy B: CREATE STATISTICS (mcv) ON country_code, city
DROP STATISTICS IF EXISTS st_lab33_addr_country_city_mcv;

ANALYZE addresses;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS extended_statistics_left FROM pg_statistic_ext WHERE stxname LIKE 'st\_lab33%';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
