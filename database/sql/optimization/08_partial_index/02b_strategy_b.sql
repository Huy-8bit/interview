-- =============================================================================
-- Lab 08 · Partial index: index only the rows you query — OPTIMIZE · Strategy B
-- Strategy B: Partial index (created_at) WHERE status = 'PENDING'
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Only the ~8.5% PENDING rows are indexed and the status column is not even
-- stored. The planner uses it when the query's WHERE implies the index
-- predicate (status = 'PENDING'). INSERTs of non-PENDING payments skip it.

CREATE INDEX ix_lab08_payments_pending_created ON payments (created_at) WHERE status = 'PENDING';

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'payments' ORDER BY 1;
         -- the predicate is visible in the definition:
         SELECT pg_get_indexdef('ix_lab08_payments_pending_created'::regclass);

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab08_payments_pending_created;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
