-- =============================================================================
-- Lab 12 · JSONB: GIN jsonb_ops vs jsonb_path_ops vs expression B-tree — OPTIMIZE · Strategy A
-- Strategy A: GIN (metadata) with the default jsonb_ops
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- jsonb_ops indexes every key and every value as separate items: supports
-- @>, ?, ?|, ?& and jsonpath @? @@. Not the ->> = comparison (Q3).

CREATE INDEX ix_lab12_users_metadata_gin ON users USING gin (metadata);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab12_users_metadata_gin;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
