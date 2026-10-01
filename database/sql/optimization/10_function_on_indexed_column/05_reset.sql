-- =============================================================================
-- Lab 10 · Function on an indexed column (sargable queries) — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Rewrite as a half-open range on the bare column (sargable)
-- (nothing to undo: query rewrite only)

-- Reset Strategy B: Expression index on the UTC date (when the query cannot be changed)
DROP INDEX IF EXISTS ix_lab10_orders_created_utc_date;

ANALYZE orders;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;   -- no ix_lab10_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
