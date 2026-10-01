-- =============================================================================
-- Lab 04 · Index Only Scan, visibility map, Heap Fetches — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: VACUUM: fill the visibility map
-- (strategy A has no object of its own: 05_reset.sql drops lab_ios)

-- Reset Strategy B: Covering index INCLUDE (total_amount) + VACUUM
DROP INDEX IF EXISTS ix_lab04_ios_created_incl;

DROP TABLE IF EXISTS lab_ios;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS lab_ios_tables_left FROM pg_class WHERE relname = 'lab_ios';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
