-- =============================================================================
-- Lab 03 · Bitmap Index Scan + Bitmap Heap Scan, BitmapAnd — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. One category: ~56k rows scattered over ~50k heap pages
-- -----------------------------------------------------------------------------

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

-- Observe:
--   * Bitmap Index Scan on idx_products_category_id: builds a bitmap of matching TIDs
--   * Bitmap Heap Scan: reads each heap page once, in physical order
--   * Heap Blocks: exact=N (one bit per row)  vs  lossy=N (one bit per page)
--   * Recheck Cond: only evaluated on lossy pages (or for lossy index types)

-- -----------------------------------------------------------------------------
-- Q2. Two indexed conditions: BitmapAnd of two indexes
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, name, price
FROM products
WHERE category_id = 48
  AND price BETWEEN 50 AND 52;

-- Observe:
--   * BitmapAnd: two Bitmap Index Scans combined in memory before touching the heap
--   * Each child scan returns many TIDs (actual rows=...), the AND keeps only a few

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
