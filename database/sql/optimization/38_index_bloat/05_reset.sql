-- =============================================================================
-- Lab 38 · Index bloat: pgstatindex and REINDEX — RESET
-- Return the database to the exact state it had before this lab.
-- Safe to run any number of times (everything is IF EXISTS / idempotent).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Reset Strategy A: REINDEX INDEX: rebuild compactly
-- (no object of its own: 05_reset.sql drops lab_index_bloat)

-- Reset Strategy B: REINDEX INDEX CONCURRENTLY: same result, no write lock
-- (no object of its own: 05_reset.sql drops lab_index_bloat)

DROP TABLE IF EXISTS lab_index_bloat;

-- Session settings possibly changed by this lab
RESET ALL;

-- Verify: the objects created by this lab are gone
SELECT count(*) AS lab_index_bloat_tables_left FROM pg_class WHERE relname = 'lab_index_bloat';   -- 0

-- Full check of the whole database (expect a single row: BASELINE OK):
--   sql/optimization/00_environment/09_verify_baseline.sql
