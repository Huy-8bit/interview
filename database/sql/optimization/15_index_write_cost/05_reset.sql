-- =============================================================================
-- Lab 15 · Indexes are not free: INSERT / UPDATE / DELETE cost and WAL — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: Four secondary indexes (a typical 'index everything' table)
DROP INDEX IF EXISTS ix_lab15_write_user;
DROP INDEX IF EXISTS ix_lab15_write_status_time;
DROP INDEX IF EXISTS ix_lab15_write_created;
DROP INDEX IF EXISTS ix_lab15_write_number;

-- Reset Strategy B: Only the one index the application really needs (user_id)
DROP INDEX IF EXISTS ix_lab15_write_user_only;

DROP TABLE IF EXISTS lab_write;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS lab_write_tables_left FROM pg_class WHERE relname = 'lab_write';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
