-- =============================================================================
-- Lab 07 · Covering index: INCLUDE vs composite key — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
-- Product 4905450 is the best seller: ~34k order lines spread over the whole order_items table
SELECT count(*) AS order_lines FROM order_items WHERE product_id = 4905450;

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

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
