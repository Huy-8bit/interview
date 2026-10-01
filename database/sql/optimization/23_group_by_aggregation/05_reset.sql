-- =============================================================================
-- Lab 23 · GROUP BY: HashAggregate vs GroupAggregate — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (experiment) work_mem = 256MB
RESET work_mem;

-- Reset Strategy B: Covering index (user_id) INCLUDE (total_amount): GroupAggregate without sort or hash
DROP INDEX IF EXISTS ix_lab23_orders_user_incl;

ANALYZE orders;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;   -- no ix_lab23_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
