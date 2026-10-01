-- =============================================================================
-- Lab 12 · JSONB: GIN jsonb_ops vs jsonb_path_ops vs expression B-tree — OPTIMIZE · Strategy B
-- Strategy B: GIN (metadata jsonb_path_ops)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- jsonb_path_ops stores one hash per path-to-value: smaller and faster for @>,
-- but it cannot answer key-existence (?) queries - Q2 falls back to Seq Scan.

CREATE INDEX ix_lab12_users_metadata_pathops ON users USING gin (metadata jsonb_path_ops);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab12_users_metadata_pathops;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
