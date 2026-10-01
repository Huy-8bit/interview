-- =============================================================================
-- Lab 03 · Bitmap Index Scan + Bitmap Heap Scan, BitmapAnd — OPTIMIZE · Strategy A
-- Strategy A: Composite index (category_id, price) replaces the BitmapAnd
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- With one index ordered by (category_id, price) the second query becomes a
-- single range scan: category_id = 48 AND price BETWEEN 50 AND 52 is one
-- contiguous slice of the index, no need to intersect two big bitmaps.

CREATE INDEX ix_lab03_products_category_price ON products (category_id, price);

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab03_products_category_price')) AS index_size;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab03_products_category_price;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
