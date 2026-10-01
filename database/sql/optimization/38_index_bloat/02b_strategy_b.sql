-- =============================================================================
-- Lab 38 · Index bloat: pgstatindex and REINDEX — OPTIMIZE · Strategy B
-- Strategy B: REINDEX INDEX CONCURRENTLY: same result, no write lock
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Builds a new index next to the old one while writes continue, then swaps them.
-- Slower, needs space for both, cannot run inside a transaction block; if it fails
-- it leaves an INVALID index named *_ccnew to drop.

REINDEX INDEX CONCURRENTLY ix_lab38_ibloat_txn;

-- Check what was created / changed:
SELECT pg_size_pretty(pg_relation_size('ix_lab38_ibloat_txn')) AS index_size, leaf_pages, avg_leaf_density
FROM pgstatindex('ix_lab38_ibloat_txn');
SELECT indexrelid::regclass, indisvalid FROM pg_index WHERE indrelid = 'lab_index_bloat'::regclass;

-- Undo only this strategy:
-- -- (no object of its own: 05_reset.sql drops lab_index_bloat)

-- Next: run 03_after.sql, compare with 01_before.sql, then 05_reset.sql.
