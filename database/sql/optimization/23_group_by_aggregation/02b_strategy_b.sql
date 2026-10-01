-- =============================================================================
-- Lab 23 · GROUP BY: HashAggregate vs GroupAggregate — OPTIMIZE · Strategy B
-- Strategy B: Covering index (user_id) INCLUDE (total_amount): GroupAggregate without sort or hash
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- GroupAggregate needs its input ordered by the group key: it then keeps only
-- ONE group in memory at a time. An index on user_id that also carries
-- total_amount delivers exactly that as an Index Only Scan.

CREATE INDEX ix_lab23_orders_user_incl ON orders (user_id) INCLUDE (total_amount);
VACUUM (ANALYZE) orders;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab23_orders_user_incl;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
