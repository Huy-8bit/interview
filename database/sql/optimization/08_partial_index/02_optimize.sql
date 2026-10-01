-- =============================================================================
-- Lab 08 · Partial index: index only the rows you query — OPTIMIZE · Strategy A
-- Strategy A: Full composite index (status, created_at)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Serves every status: equality on status, then the rows come out ordered by
-- created_at, so the LIMIT stops after 100 entries. It indexes all 5.1M rows.

CREATE INDEX ix_lab08_payments_status_created ON payments (status, created_at);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'payments' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab08_payments_status_created;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
