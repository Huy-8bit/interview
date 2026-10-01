-- =============================================================================
-- Lab 06 · Column order in a composite index: equality vs range — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (rating, created_at): equality column first
DROP INDEX IF EXISTS ix_lab06_reviews_rating_created;

-- Reset Strategy B: (created_at, rating): range column first
DROP INDEX IF EXISTS ix_lab06_reviews_created_rating;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'reviews' ORDER BY 1;   -- no ix_lab06_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
