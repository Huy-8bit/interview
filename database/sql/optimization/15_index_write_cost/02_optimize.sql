-- =============================================================================
-- Lab 15 · Indexes are not free: INSERT / UPDATE / DELETE cost and WAL — OPTIMIZE · Strategy A
-- Strategy A: Four secondary indexes (a typical 'index everything' table)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- user_id, (status, created_at), created_at and a UNIQUE order_number: every
-- inserted row now writes 1 heap tuple + 5 index entries (with the PK), each
-- with its own WAL records and dirty pages.

CREATE INDEX ix_lab15_write_user        ON lab_write (user_id);
CREATE INDEX ix_lab15_write_status_time ON lab_write (status, created_at);
CREATE INDEX ix_lab15_write_created     ON lab_write (created_at);
CREATE UNIQUE INDEX ix_lab15_write_number ON lab_write (order_number);

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('lab_write')) AS heap,
       pg_size_pretty(pg_indexes_size('lab_write'))  AS indexes;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab15_write_user;
-- DROP INDEX IF EXISTS ix_lab15_write_status_time;
-- DROP INDEX IF EXISTS ix_lab15_write_created;
-- DROP INDEX IF EXISTS ix_lab15_write_number;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
