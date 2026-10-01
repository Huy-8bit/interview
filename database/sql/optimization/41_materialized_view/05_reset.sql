-- =============================================================================
-- Lab 41 · Materialized view: precompute an expensive aggregate — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: CREATE MATERIALIZED VIEW + unique index (for REFRESH CONCURRENTLY)
DROP MATERIALIZED VIEW IF EXISTS mv_lab41_daily_revenue;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS lab_materialized_views_left FROM pg_matviews WHERE matviewname LIKE 'mv\_lab41%';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
