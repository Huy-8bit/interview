-- =============================================================================
-- Lab 09 · Expression index: lower(username) — OPTIMIZE · Strategy A
-- Strategy A: Expression index on lower(username)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- An expression index stores the RESULT of the expression for every row. It is
-- used when the query contains the very same expression (lower(username) = ...).
-- The function must be IMMUTABLE. ANALYZE also gathers statistics on the
-- expression (visible in pg_stats under the index name).

CREATE INDEX ix_lab09_users_username_lower ON users (lower(username));
ANALYZE users;

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;
         SELECT tablename, attname, n_distinct FROM pg_stats WHERE tablename = 'ix_lab09_users_username_lower';

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab09_users_username_lower;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
