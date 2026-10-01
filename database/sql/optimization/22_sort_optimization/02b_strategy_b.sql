-- =============================================================================
-- Lab 22 · Sort: in-memory quicksort vs external merge vs no sort — OPTIMIZE · Strategy B
-- Strategy B: Index that already provides the order: (total_amount DESC) INCLUDE (id, user_id)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- The fastest sort is the one that never happens: an index in the requested
-- order, with every selected column, turns the query into an Index Only Scan
-- that streams rows already sorted (and a LIMIT can stop immediately).

CREATE INDEX ix_lab22_orders_amount_incl ON orders (total_amount DESC) INCLUDE (id, user_id);
VACUUM (ANALYZE) orders;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab22_orders_amount_incl;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
