-- =============================================================================
-- Lab 20 · Large join: a 5-table revenue report — OPTIMIZE · Strategy B
-- Strategy B: Narrow the wide table: covering index products (id) INCLUDE (category_id)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- The query needs only id and category_id of products, but every lookup reads a
-- 2 GB heap of ~400-byte rows (name, description, attributes...). A covering
-- index makes the lookup an Index Only Scan over a much smaller structure.

CREATE INDEX ix_lab20_products_id_category ON products (id) INCLUDE (category_id);
VACUUM (ANALYZE) products;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab20_products_id_category;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
