-- =============================================================================
-- Lab 36 · VACUUM: dead tuples, visibility map, VACUUM vs VACUUM FULL — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: VACUUM (VERBOSE): remove dead tuples, set the visibility map
-- (no object of its own: 05_reset.sql drops lab_vacuum)

-- Reset Strategy B: VACUUM FULL: rewrite the table compactly
-- (no object of its own: 05_reset.sql drops lab_vacuum)

DROP TABLE IF EXISTS lab_vacuum;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS lab_vacuum_tables_left FROM pg_class WHERE relname = 'lab_vacuum';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
