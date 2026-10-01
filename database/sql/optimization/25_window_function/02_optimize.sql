-- =============================================================================
-- Lab 25 · Window functions: the sort behind PARTITION BY ... ORDER BY — OPTIMIZE · Strategy A
-- Strategy A: Index (user_id, created_at DESC): the window's order comes from the index
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- With rows read in (user_id, created_at DESC) order the WindowAgg needs no
-- sort at all, and with Run Condition it can skip the rest of each partition.

CREATE INDEX ix_lab25_orders_user_created ON orders (user_id, created_at DESC);
ANALYZE orders;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab25_orders_user_created;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
