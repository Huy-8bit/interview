-- =============================================================================
-- Lab 29 · Pagination with OFFSET: the cost of deep pages — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (experiment) 'deferred join' WITHOUT a suitable index
-- (nothing to undo: query rewrite only)

-- Reset Strategy B: Deferred join + index (created_at DESC) INCLUDE (id)
DROP INDEX IF EXISTS ix_lab29_orders_created_incl_id;

ANALYZE orders;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;   -- no ix_lab29_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
