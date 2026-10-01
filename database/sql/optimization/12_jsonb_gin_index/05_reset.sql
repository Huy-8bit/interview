-- =============================================================================
-- Lab 12 · JSONB: GIN jsonb_ops vs jsonb_path_ops vs expression B-tree — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: GIN (metadata) with the default jsonb_ops
DROP INDEX IF EXISTS ix_lab12_users_metadata_gin;

-- Reset Strategy B: GIN (metadata jsonb_path_ops)
DROP INDEX IF EXISTS ix_lab12_users_metadata_pathops;

-- Reset Strategy C: B-tree expression index on (metadata ->> 'preferred_language')
DROP INDEX IF EXISTS ix_lab12_users_pref_lang;

ANALYZE users;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT indexname FROM pg_indexes WHERE tablename = 'users' ORDER BY 1;   -- no ix_lab12_*

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
