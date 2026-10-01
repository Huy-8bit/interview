-- =============================================================================
-- Lab 13 · LIKE 'prefix%' vs ILIKE '%contains%': pattern ops vs trigram — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

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

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
