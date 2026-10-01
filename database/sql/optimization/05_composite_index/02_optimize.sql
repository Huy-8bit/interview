-- =============================================================================
-- Lab 05 · Composite index: filter + sort in one index — OPTIMIZE · Strategy A
-- Strategy A: Indexes on (category_id, status) and (user_id, status)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Step 2 of the progression: both equality columns in the index key.
-- The filter becomes part of Index Cond, but the result must still be sorted
-- (ORDER BY price / created_at is not in the index).

CREATE INDEX ix_lab05_products_cat_status ON products (category_id, status);
CREATE INDEX ix_lab05_orders_user_status  ON orders (user_id, status);
ANALYZE products, orders;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab05_products_cat_status;
-- DROP INDEX IF EXISTS ix_lab05_orders_user_status;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
