-- =============================================================================
-- Lab 02 · Selectivity: the same index, different plans — OPTIMIZE · Strategy A
-- Strategy A: B-tree index on payments(status)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- A plain index on a low-cardinality column (4 distinct values). It helps the
-- rare values and is ignored for the common one: the planner multiplies
-- the selectivity from pg_stats by the table size and compares the cost of
-- a Seq Scan with the cost of index + random heap pages.

CREATE INDEX ix_lab02_payments_status ON payments (status);

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab02_payments_status')) AS index_size;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab02_payments_status;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
