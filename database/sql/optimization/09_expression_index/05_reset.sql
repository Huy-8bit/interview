-- =============================================================================
-- Lab 09 · Expression index: lower(username) — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Expression index on lower(username)
DROP INDEX IF EXISTS ix_lab09_users_username_lower;

-- Reset Strategy B: No DDL: rewrite the email query to match the existing lower(email) index
-- (nothing to undo: query rewrite only)

ANALYZE users;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;   -- no ix_lab09_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
