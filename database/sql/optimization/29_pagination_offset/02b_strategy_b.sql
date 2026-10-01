-- =============================================================================
-- Lab 29 · Pagination with OFFSET: the cost of deep pages — OPTIMIZE · Strategy B
-- Strategy B: Deferred join + index (created_at DESC) INCLUDE (id)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- With id inside the index the subquery becomes an Index Only Scan: skipping
-- 1,000,000 entries reads only index pages (dense, ~ few thousand), then 50 heap
-- lookups fetch the full rows. Deep pages stay O(offset), but much cheaper.

CREATE INDEX ix_lab29_orders_created_incl_id ON orders (created_at DESC) INCLUDE (id);
VACUUM (ANALYZE) orders;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'orders' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab29_orders_created_incl_id;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
