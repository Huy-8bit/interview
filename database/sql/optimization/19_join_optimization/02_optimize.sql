-- =============================================================================
-- Lab 19 · Join optimization: the unindexed foreign key — OPTIMIZE · Strategy A
-- Strategy A: Index the foreign key column: reviews(order_id)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- With an index on the FK column the join can become a Nested Loop that looks up
-- the reviews of each order, and the FK trigger fired by DELETE/UPDATE on orders
-- becomes an index lookup instead of a full scan of reviews.

CREATE INDEX ix_lab19_reviews_order_id ON reviews (order_id);
ANALYZE reviews;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'reviews' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab19_reviews_order_id;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
