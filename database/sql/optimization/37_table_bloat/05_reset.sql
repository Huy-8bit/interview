-- =============================================================================
-- Lab 37 · Table bloat: VACUUM FULL vs CLUSTER — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: VACUUM FULL: compact rewrite
-- (no object of its own: 05_reset.sql drops lab_bloat)

-- Reset Strategy B: CLUSTER ... USING ix_lab37_bloat_user: compact AND physically ordered by user_id
-- (no object of its own: 05_reset.sql drops lab_bloat)

DROP TABLE IF EXISTS lab_bloat;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS lab_bloat_tables_left FROM pg_class WHERE relname = 'lab_bloat';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
