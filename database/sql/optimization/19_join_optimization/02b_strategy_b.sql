-- =============================================================================
-- Lab 19 · Join optimization: the unindexed foreign key — OPTIMIZE · Strategy B
-- Strategy B: Partial index reviews(order_id) WHERE order_id IS NOT NULL
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- ~25% of reviews are unverified and have order_id NULL: they can never match a
-- join on order_id or an FK check. A partial index skips them (smaller); both
-- 'r.order_id = o.id' and the trigger's 'order_id = $1' imply NOT NULL, so the
-- planner can use it.

CREATE INDEX ix_lab19_reviews_order_id_nn ON reviews (order_id) WHERE order_id IS NOT NULL;
ANALYZE reviews;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'reviews' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab19_reviews_order_id_nn;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
