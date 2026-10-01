-- =============================================================================
-- Lab 13 · LIKE 'prefix%' vs ILIKE '%contains%': pattern ops vs trigram — OPTIMIZE · Strategy B
-- Strategy B: GIN (name gin_trgm_ops) - pg_trgm (extension already installed)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- pg_trgm splits text into 3-character grams ('air' 'ir ' ' fr' ...). The GIN
-- index finds rows containing all grams of the pattern, then rechecks. Serves
-- LIKE / ILIKE with leading %, prefix searches, regex, and similarity (%).

CREATE INDEX ix_lab13_products_name_trgm ON products USING gin (name gin_trgm_ops);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'products' ORDER BY 1;
         SELECT show_trgm('air fryer');

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab13_products_name_trgm;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
