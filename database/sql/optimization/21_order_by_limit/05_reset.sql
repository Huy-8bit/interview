-- =============================================================================
-- Lab 21 · ORDER BY ... LIMIT: top-N heapsort vs Index Scan Backward — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Index on payments(created_at)
DROP INDEX IF EXISTS ix_lab21_payments_created;

-- Reset Strategy B: Index on payments(status, created_at)
DROP INDEX IF EXISTS ix_lab21_payments_status_created;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'payments' ORDER BY 1;   -- no ix_lab21_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
