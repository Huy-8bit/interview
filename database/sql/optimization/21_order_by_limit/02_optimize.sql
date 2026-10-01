-- =============================================================================
-- Lab 21 · ORDER BY ... LIMIT: top-N heapsort vs Index Scan Backward — OPTIMIZE · Strategy A
-- Strategy A: Index on payments(created_at)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- The index already holds the rows in created_at order: reading it BACKWARD
-- returns the newest first, and the Limit stops after 50 rows. No Sort node.
-- For Q2 the backward scan must skip non-FAILED rows (Filter) until 50 match.

CREATE INDEX ix_lab21_payments_created ON payments (created_at);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'payments' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab21_payments_created;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
