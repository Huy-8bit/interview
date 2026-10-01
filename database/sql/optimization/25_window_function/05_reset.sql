-- =============================================================================
-- Lab 25 · Window functions: the sort behind PARTITION BY ... ORDER BY — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Index (user_id, created_at DESC): the window's order comes from the index
DROP INDEX IF EXISTS ix_lab25_orders_user_created;

-- Reset Strategy B: Rewrite with DISTINCT ON (user_id)
-- (nothing to undo: query rewrite only)

ANALYZE orders;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;   -- no ix_lab25_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
