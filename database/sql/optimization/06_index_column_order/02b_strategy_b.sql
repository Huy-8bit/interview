-- =============================================================================
-- Lab 06 · Column order in a composite index: equality vs range — OPTIMIZE · Strategy B
-- Strategy B: (created_at, rating): range column first
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Entries are sorted by created_at first. For Q1 the index can seek to
-- '2026-09-01' but then must read EVERY rating in the range and check
-- rating = 1 on each entry (it appears as Index Cond, but it does not
-- narrow the scanned range). Q2 is served perfectly; Q3 cannot seek.

CREATE INDEX ix_lab06_reviews_created_rating ON reviews (created_at, rating);

-- Check what was created / changed:
SELECT indexname, pg_size_pretty(pg_relation_size(format('%I', indexname)::regclass)) AS size
FROM pg_indexes WHERE tablename = 'reviews' ORDER BY 1;

-- Undo only this strategy:
-- DROP INDEX IF EXISTS ix_lab06_reviews_created_rating;

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
