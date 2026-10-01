-- =============================================================================
-- Lab 03 · Bitmap Index Scan + Bitmap Heap Scan, BitmapAnd — OPTIMIZE · Strategy B
-- Strategy B: (experiment) tiny work_mem: the planner changes plan, a forced bitmap goes lossy
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- The bitmap must fit in work_mem. When it does not, PostgreSQL degrades it
-- to one bit per PAGE ("lossy"): every row of those pages must then be
-- rechecked (Rows Removed by Index Recheck). The planner knows this and
-- includes the recheck cost: with a tiny work_mem it may simply pick another
-- plan. Q1 shows what it picks; Q2 also disables plain index scans to force
-- the bitmap and show the lossy pages. No DDL: session settings only, reset.

-- -----------------------------------------------------------------------------
-- Q1. Q1 with work_mem = 64kB (planner free to choose)
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET work_mem = '64kB';

-- 1) The query itself
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

RESET work_mem;

-- Observe:
--   * Did the planner keep the Bitmap Heap Scan? (on the author's run: no, Index Scan)

-- -----------------------------------------------------------------------------
-- Q2. Q1 with work_mem = 64kB and enable_indexscan = off (bitmap forced)
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET work_mem = '64kB';
SET enable_indexscan = off;

-- 1) The query itself
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), round(avg(price), 2) AS avg_price
FROM products
WHERE category_id = 48;

RESET work_mem;
RESET enable_indexscan;

-- Observe:
--   * Heap Blocks: exact=... lossy=...
--   * Rows Removed by Index Recheck: rows of lossy pages that did not match

-- Undo only this strategy:
-- RESET work_mem;
-- RESET enable_indexscan;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
