-- =============================================================================
-- Lab 13 · LIKE 'prefix%' vs ILIKE '%contains%': pattern ops vs trigram — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: B-tree (name varchar_pattern_ops)
DROP INDEX IF EXISTS ix_lab13_products_name_pattern;

-- Reset Strategy B: GIN (name gin_trgm_ops) - pg_trgm (extension already installed)
DROP INDEX IF EXISTS ix_lab13_products_name_trgm;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;   -- no ix_lab13_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
