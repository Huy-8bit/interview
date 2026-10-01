-- =============================================================================
-- Lab 05 · Composite index: filter + sort in one index — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Indexes on (category_id, status) and (user_id, status)
DROP INDEX IF EXISTS ix_lab05_products_cat_status;
DROP INDEX IF EXISTS ix_lab05_orders_user_status;

-- Reset Strategy B: Indexes on (category_id, status, price DESC) and (user_id, status, created_at DESC)
DROP INDEX IF EXISTS ix_lab05_products_cat_status_price;
DROP INDEX IF EXISTS ix_lab05_orders_user_status_created;

ANALYZE products, orders;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes
WHERE tablename IN ('products', 'orders') AND indexname LIKE 'ix\_lab05%';   -- 0 rows

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
