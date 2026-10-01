-- =============================================================================
-- Lab 01 · Seq Scan vs Index Scan — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: B-tree index on users(phone)
DROP INDEX IF EXISTS ix_lab01_users_phone;

-- Reset Strategy B: Hash index on users(phone)
DROP INDEX IF EXISTS ix_lab01_users_phone_hash;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;   -- no ix_lab01_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
