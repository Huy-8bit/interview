-- =============================================================================
-- Lab 13 · LIKE 'prefix%' vs ILIKE '%contains%': pattern ops vs trigram — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT datcollate FROM pg_database WHERE datname = current_database();   -- en_US.utf8, not C
SELECT count(*) FILTER (WHERE name LIKE 'Sony Pro%')    AS prefix_matches,
       count(*) FILTER (WHERE name ILIKE '%air fryer%') AS contains_matches
FROM products;

-- -----------------------------------------------------------------------------
-- Q1. Prefix search: names starting with 'Sony Pro'
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM products
WHERE name LIKE 'Sony Pro%';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM products
WHERE name LIKE 'Sony Pro%';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM products
WHERE name LIKE 'Sony Pro%';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM products
WHERE name LIKE 'Sony Pro%';

-- Observe:
--   * Seq Scan: there is no index on name (and a plain B-tree under a non-C collation
--   * could not serve LIKE anyway)

-- -----------------------------------------------------------------------------
-- Q2. Contains search: names containing 'air fryer' (case-insensitive)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM products
WHERE name ILIKE '%air fryer%';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM products
WHERE name ILIKE '%air fryer%';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM products
WHERE name ILIKE '%air fryer%';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM products
WHERE name ILIKE '%air fryer%';

-- Observe:
--   * A leading % means 'can start anywhere': no B-tree can help

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
