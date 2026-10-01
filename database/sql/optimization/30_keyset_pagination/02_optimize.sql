-- =============================================================================
-- Lab 30 · Keyset (seek) pagination — OPTIMIZE · Strategy A
-- Strategy A: Index on (created_at DESC, id DESC): the row comparison becomes an index range
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- An index ordered exactly like the ORDER BY (including the tie-breaker) lets the
-- planner use ROW(created_at, id) < ROW(...) as an Index Cond and return 50 rows
-- with no sort, whatever the page number.

CREATE INDEX ix_lab30_orders_created_id ON orders (created_at DESC, id DESC);
ANALYZE orders;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab30_orders_created_id;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
