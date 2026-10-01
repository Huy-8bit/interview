-- =============================================================================
-- Lab 07 · Covering index: INCLUDE vs composite key — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: (product_id) INCLUDE (quantity, unit_price)
DROP INDEX IF EXISTS ix_lab07_items_product_incl;

-- Reset Strategy B: (product_id, quantity, unit_price) as key columns
DROP INDEX IF EXISTS ix_lab07_items_product_qty_price;

ANALYZE order_items;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'order_items' ORDER BY 1;   -- no ix_lab07_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
