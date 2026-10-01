-- =============================================================================
-- Lab 06 · Column order in a composite index: equality vs range — OPTIMIZE · Strategy A
-- Strategy A: (rating, created_at): equality column first
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- All entries with rating = 1 are adjacent in the index, sorted by created_at:
-- Q1 = one seek to (1, '2026-09-01') + read forward until rating changes.

CREATE INDEX ix_lab06_reviews_rating_created ON reviews (rating, created_at);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'reviews' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab06_reviews_rating_created;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
