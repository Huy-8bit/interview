-- =============================================================================
-- Lab 03 · Bitmap Index Scan + Bitmap Heap Scan, BitmapAnd — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Composite index (category_id, price) replaces the BitmapAnd
DROP INDEX IF EXISTS ix_lab03_products_category_price;

-- Reset Strategy B: (experiment) tiny work_mem: the planner changes plan, a forced bitmap goes lossy
RESET work_mem;
RESET enable_indexscan;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;   -- no ix_lab03_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
