-- =============================================================================
-- Lab 26 · CTE: inlined, MATERIALIZED, NOT MATERIALIZED — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (experiment) AS MATERIALIZED on the single-use CTE
-- (nothing to undo: query rewrite only)

-- Reset Strategy B: (experiment) NOT MATERIALIZED on the CTE that is used twice
-- (nothing to undo: query rewrite only)

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT 'lab 26 creates no objects' AS note;

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
