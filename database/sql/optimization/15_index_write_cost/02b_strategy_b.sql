-- =============================================================================
-- Lab 15 · Indexes are not free: INSERT / UPDATE / DELETE cost and WAL — OPTIMIZE · Strategy B
-- Strategy B: Only the one index the application really needs (user_id)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Same table with a single secondary index: the cost sits between the bare
-- table and strategy A. The UPDATE of status can be cheaper again because no
-- index contains status (HOT is possible when the page has free space).

CREATE INDEX ix_lab15_write_user_only ON lab_write (user_id);

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab15_write_user_only;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
