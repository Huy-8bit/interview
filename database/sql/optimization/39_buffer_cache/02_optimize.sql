-- =============================================================================
-- Lab 39 · Buffer cache: shared hit vs read, cold vs warm, working set — OPTIMIZE · Strategy A
-- Strategy A: Shrink the working set: covering index (created_at) INCLUDE (total_amount)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- The query needs 2 columns of ~800k rows, but reads whole heap pages (~1.5KB of
-- other columns per row). A covering index stores just those 2 columns, densely:
-- the pages needed fit in shared_buffers, so repeated runs are served from the
-- cache. Optimizing the working set is optimizing the cache hit ratio.

CREATE INDEX ix_lab39_orders_created_amount ON orders (created_at) INCLUDE (total_amount);
VACUUM (ANALYZE) orders;

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab39_orders_created_amount')) AS index_size;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab39_orders_created_amount;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
