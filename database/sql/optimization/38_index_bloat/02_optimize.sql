-- =============================================================================
-- Lab 38 · Index bloat: pgstatindex and REINDEX — OPTIMIZE · Strategy A
-- Strategy A: REINDEX INDEX: rebuild compactly
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- What / why:
-- VACUUM removes dead index entries but B-tree pages are only recycled when they
-- become completely EMPTY - half-empty pages stay. REINDEX builds the index from
-- scratch with full pages (fillfactor 90). Plain REINDEX blocks writes to the table
-- (and reads that would use this index) while it runs.

REINDEX INDEX ix_lab38_ibloat_txn;

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab38_ibloat_txn')) AS index_size, leaf_pages, avg_leaf_density
FROM pgstatindex('ix_lab38_ibloat_txn');

-- Undo only this strategy:
-- -- (no object of its own: 05_reset.sql drops lab_index_bloat)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
