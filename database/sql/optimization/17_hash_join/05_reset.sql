-- =============================================================================
-- Lab 17 · Hash Join: build the small side, probe with the big side — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (experiment) work_mem = 1MB: the hash table spills to disk (Batches > 1)
RESET work_mem;

-- Reset Strategy B: (experiment) SET enable_hashjoin = off: the alternative join
RESET enable_hashjoin;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT 'lab 17 creates no objects' AS note;

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
