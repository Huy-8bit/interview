-- =============================================================================
-- Lab 19 · Join optimization: the unindexed foreign key — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Index the foreign key column: reviews(order_id)
DROP INDEX IF EXISTS ix_lab19_reviews_order_id;

-- Reset Strategy B: Partial index reviews(order_id) WHERE order_id IS NOT NULL
DROP INDEX IF EXISTS ix_lab19_reviews_order_id_nn;

ANALYZE reviews;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'reviews' ORDER BY 1;   -- no ix_lab19_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
