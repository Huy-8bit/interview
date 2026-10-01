-- =============================================================================
-- Lab 39 · Buffer cache: shared hit vs read, cold vs warm, working set — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Shrink the working set: covering index (created_at) INCLUDE (total_amount)
DROP INDEX IF EXISTS ix_lab39_orders_created_amount;

ANALYZE orders;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;   -- no ix_lab39_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
