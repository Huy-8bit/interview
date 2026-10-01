-- =============================================================================
-- Lab 02 · Selectivity: the same index, different plans — OPTIMIZE · Strategy B
-- Strategy B: Partial index: only the rows that are NOT 'SUCCEEDED'
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- The index is never used for SUCCEEDED, so why store 79% of the table in it?
-- A partial index keeps only the rows matching its WHERE clause: ~5x smaller,
-- cheaper to maintain on INSERT, and still usable for every query whose WHERE
-- implies status <> 'SUCCEEDED' (e.g. status = 'PENDING').

CREATE INDEX ix_lab02_payments_status_not_succeeded
    ON payments (status) WHERE status <> 'SUCCEEDED';

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab02_payments_status_not_succeeded')) AS index_size;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab02_payments_status_not_succeeded;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
