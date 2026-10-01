-- =============================================================================
-- Lab 05 · Composite index: filter + sort in one index — OPTIMIZE · Strategy B
-- Strategy B: Indexes on (category_id, status, price DESC) and (user_id, status, created_at DESC)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Step 3: equality columns first, then the ORDER BY column in the requested
-- direction. The index returns rows already filtered AND sorted: the LIMIT
-- can stop after reading exactly 20 index entries; no Sort node at all.

CREATE INDEX ix_lab05_products_cat_status_price ON products (category_id, status, price DESC);
CREATE INDEX ix_lab05_orders_user_status_created ON orders (user_id, status, created_at DESC);
ANALYZE products, orders;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab05_products_cat_status_price;
-- DROP INDEX IF EXISTS ix_lab05_orders_user_status_created;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
