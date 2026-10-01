-- =============================================================================
-- Lab 21 · ORDER BY ... LIMIT: top-N heapsort vs Index Scan Backward — OPTIMIZE · Strategy B
-- Strategy B: Index on payments(status, created_at)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Perfect for Q2 (equality + order): seek to status = 'FAILED', read backward 50
-- entries. Useless for Q1 (no condition on the leading column status).

CREATE INDEX ix_lab21_payments_status_created ON payments (status, created_at);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'payments' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab21_payments_status_created;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
