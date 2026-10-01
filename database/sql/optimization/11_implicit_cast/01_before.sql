-- =============================================================================
-- Lab 11 · Implicit casts that disable an index — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Context: how big is the data this query touches?
SELECT column_name, data_type, character_maximum_length FROM information_schema.columns
WHERE (table_name, column_name) IN (('orders', 'id'), ('orders', 'user_id'), ('users', 'phone'));

-- -----------------------------------------------------------------------------
-- Q1. bigint column compared with a numeric literal
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000.0;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000.0;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000.0;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, total_amount
FROM orders
WHERE id = 250000.0;

-- Observe:
--   * Filter: ((id)::numeric = 250000.0) -> the COLUMN is cast, for every row
--   * There is no bigint = numeric operator that the pk index supports

-- -----------------------------------------------------------------------------
-- Q2. Casting the column to text to compare with a string
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, order_number, total_amount
FROM orders
WHERE user_id::text = '1600976';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, order_number, total_amount
FROM orders
WHERE user_id::text = '1600976';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, order_number, total_amount
FROM orders
WHERE user_id::text = '1600976';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, order_number, total_amount
FROM orders
WHERE user_id::text = '1600976';

-- Observe:
--   * Filter: ((user_id)::text = '1600976'::text) - idx_orders_user_id unusable

-- -----------------------------------------------------------------------------
-- Q3. varchar column compared with a char(n) parameter
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username
FROM users
WHERE phone = '+1-377-523-1035'::char(15);

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username
FROM users
WHERE phone = '+1-377-523-1035'::char(15);

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username
FROM users
WHERE phone = '+1-377-523-1035'::char(15);

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username
FROM users
WHERE phone = '+1-377-523-1035'::char(15);

-- Observe:
--   * Filter: ((phone)::bpchar = ...) - the column is converted to the parameter's type
--   * (drivers / ORMs that bind parameters with the wrong type produce exactly this)

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
