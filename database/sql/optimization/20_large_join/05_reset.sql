-- =============================================================================
-- Lab 20 · Large join: a 5-table revenue report — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Rewrite: aggregate order lines per product BEFORE joining products
-- (nothing to undo: query rewrite only)

-- Reset Strategy B: Narrow the wide table: covering index products (id) INCLUDE (category_id)
DROP INDEX IF EXISTS ix_lab20_products_id_category;

-- Reset Strategy C: (experiment) more parallel workers: max_parallel_workers_per_gather = 4
RESET max_parallel_workers_per_gather;

ANALYZE products;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;   -- no ix_lab20_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
