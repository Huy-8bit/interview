-- =============================================================================
-- Lab 32 · Planner statistics: n_distinct, MCV, histogram, correlation — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Bigger sample for one column: SET STATISTICS 1000 + ANALYZE
ALTER TABLE orders ALTER COLUMN user_id SET STATISTICS -1;

-- Reset Strategy B: Override n_distinct manually: ALTER COLUMN ... SET (n_distinct = ...)
ALTER TABLE orders ALTER COLUMN user_id RESET (n_distinct);

ANALYZE orders;   -- rebuild the statistics with the default settings

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT attname, attstattarget, attoptions FROM pg_attribute
WHERE attrelid = 'orders'::regclass AND attname = 'user_id';   -- -1, NULL

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
