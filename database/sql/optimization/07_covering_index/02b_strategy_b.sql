-- =============================================================================
-- Lab 07 · Covering index: INCLUDE vs composite key — OPTIMIZE · Strategy B
-- Strategy B: (product_id, quantity, unit_price) as key columns
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Same columns, but as KEY columns: also usable for Index Only Scan, and in
-- addition sorted (ORDER BY product_id, quantity) and searchable on quantity.
-- Compare the size with strategy A and with the existing idx_order_items_product_id:
-- B-tree deduplication (PG13+) merges entries with identical keys - an index
-- with extra columns has far fewer identical keys.

CREATE INDEX ix_lab07_items_product_qty_price ON order_items (product_id, quantity, unit_price);
VACUUM (ANALYZE) order_items;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'order_items' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab07_items_product_qty_price;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
