-- =============================================================================
-- Lab 07 · Covering index: INCLUDE vs composite key — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Units sold and revenue of one product
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*) AS lines, sum(quantity) AS units, round(avg(unit_price), 2) AS avg_price
FROM order_items
WHERE product_id = 4905450;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*) AS lines, sum(quantity) AS units, round(avg(unit_price), 2) AS avg_price
FROM order_items
WHERE product_id = 4905450;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*) AS lines, sum(quantity) AS units, round(avg(unit_price), 2) AS avg_price
FROM order_items
WHERE product_id = 4905450;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*) AS lines, sum(quantity) AS units, round(avg(unit_price), 2) AS avg_price
FROM order_items
WHERE product_id = 4905450;

-- Observe:
--   * Bitmap Index Scan finds the rows quickly (few index pages)...
--   * ...then Bitmap Heap Scan reads ~one heap page PER ROW: Heap Blocks: exact=...

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
