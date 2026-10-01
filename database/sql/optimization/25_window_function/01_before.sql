-- =============================================================================
-- Lab 25 · Window functions: the sort behind PARTITION BY ... ORDER BY — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Latest order of each customer (users 1..200,000) with row_number()
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, user_id, status, total_amount, created_at
FROM (
  SELECT o.id, o.user_id, o.status, o.total_amount, o.created_at,
         row_number() OVER (PARTITION BY o.user_id ORDER BY o.created_at DESC) AS rn
  FROM orders o
  WHERE o.user_id BETWEEN 1 AND 200000
) s
WHERE rn = 1;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, user_id, status, total_amount, created_at
FROM (
  SELECT o.id, o.user_id, o.status, o.total_amount, o.created_at,
         row_number() OVER (PARTITION BY o.user_id ORDER BY o.created_at DESC) AS rn
  FROM orders o
  WHERE o.user_id BETWEEN 1 AND 200000
) s
WHERE rn = 1;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, user_id, status, total_amount, created_at
FROM (
  SELECT o.id, o.user_id, o.status, o.total_amount, o.created_at,
         row_number() OVER (PARTITION BY o.user_id ORDER BY o.created_at DESC) AS rn
  FROM orders o
  WHERE o.user_id BETWEEN 1 AND 200000
) s
WHERE rn = 1;

-- Observe:
--   * WindowAgg needs rows ordered by (user_id, created_at DESC): look for Sort or
--   * Incremental Sort (Presorted Key: user_id) under it
--   * Run Condition: row_number() <= 1 (PG15+): stops computing a partition early

-- -----------------------------------------------------------------------------
-- Q2. Price rank inside one category (281k products)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, name, price, rank() OVER (ORDER BY price DESC) AS price_rank
FROM products
WHERE category_id = 37
ORDER BY price_rank
LIMIT 10;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, name, price, rank() OVER (ORDER BY price DESC) AS price_rank
FROM products
WHERE category_id = 37
ORDER BY price_rank
LIMIT 10;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, name, price, rank() OVER (ORDER BY price DESC) AS price_rank
FROM products
WHERE category_id = 37
ORDER BY price_rank
LIMIT 10;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, name, price, rank() OVER (ORDER BY price DESC) AS price_rank
FROM products
WHERE category_id = 37
ORDER BY price_rank
LIMIT 10;

-- Observe:
--   * Sort of the whole category before WindowAgg (rank needs all rows ordered)

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
