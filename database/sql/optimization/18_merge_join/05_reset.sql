-- =============================================================================
-- Lab 18 · Merge Join: two inputs already sorted on the join key — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (experiment) SET enable_mergejoin = off
RESET enable_mergejoin;

-- Reset Strategy B: (experiment) Merge join on an UNINDEXED key needs an explicit Sort
RESET enable_hashjoin;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT 'lab 18 creates no objects' AS note;

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
