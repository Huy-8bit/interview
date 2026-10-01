-- =============================================================================
-- Lab 14 · OR conditions: BitmapOr, missing index, OR across a join — OPTIMIZE · Strategy A
-- Strategy A: Index the missing column (users.phone)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- Fixes Q2: with an index on each OR branch the planner builds one bitmap per
-- branch and ORs them (BitmapOr).

CREATE INDEX ix_lab14_users_phone ON users (phone);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab14_users_phone;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
