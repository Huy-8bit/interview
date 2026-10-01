-- =============================================================================
-- Lab 07 · Covering index: INCLUDE vs composite key — OPTIMIZE · Strategy A
-- Strategy A: (product_id) INCLUDE (quantity, unit_price)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- INCLUDE columns are stored in the index leaf pages only, as payload: they are
-- not part of the search key and not sorted. The query becomes an Index Only
-- Scan: no heap access (after VACUUM, Heap Fetches: 0).

CREATE INDEX ix_lab07_items_product_incl ON order_items (product_id) INCLUDE (quantity, unit_price);
VACUUM (ANALYZE) order_items;   -- refresh the visibility map for Index Only Scans

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'order_items' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab07_items_product_incl;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
