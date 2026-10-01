-- =============================================================================
-- Lab 08 · Partial index: index only the rows you query — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Full composite index (status, created_at)
DROP INDEX IF EXISTS ix_lab08_payments_status_created;

-- Reset Strategy B: Partial index (created_at) WHERE status = 'PENDING'
DROP INDEX IF EXISTS ix_lab08_payments_pending_created;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'payments' ORDER BY 1;   -- no ix_lab08_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
