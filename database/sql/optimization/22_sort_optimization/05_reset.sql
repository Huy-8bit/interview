-- =============================================================================
-- Lab 22 · Sort: in-memory quicksort vs external merge vs no sort — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (experiment) work_mem = 512MB for this session
RESET work_mem;

-- Reset Strategy B: Index that already provides the order: (total_amount DESC) INCLUDE (id, user_id)
DROP INDEX IF EXISTS ix_lab22_orders_amount_incl;

ANALYZE orders;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;   -- no ix_lab22_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
