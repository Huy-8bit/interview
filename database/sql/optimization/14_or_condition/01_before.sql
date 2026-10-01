-- =============================================================================
-- Lab 14 · OR conditions: BitmapOr, missing index, OR across a join — BEFORE (baseline)
-- The query as it runs today, before any optimization.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. OR of two indexed columns of the same table
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR username = 'jessica.reyes4242';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR username = 'jessica.reyes4242';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR username = 'jessica.reyes4242';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR username = 'jessica.reyes4242';

-- Observe:
--   * BitmapOr of two Bitmap Index Scans (ux_users_email_lower, uq_users_username)

-- -----------------------------------------------------------------------------
-- Q2. OR where one side has NO index
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR phone = '+1-236-702-0729';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR phone = '+1-236-702-0729';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR phone = '+1-236-702-0729';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE lower(email) = 'sarah.brown2037@gmail.com'
   OR phone = '+1-236-702-0729';

-- Observe:
--   * Seq Scan: a row can match through EITHER branch, so if one branch needs a full scan
--   * the whole OR needs it

-- -----------------------------------------------------------------------------
-- Q3. OR across two joined tables
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241218-00250000'
   OR u.username = 'jessica.reyes4242';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241218-00250000'
   OR u.username = 'jessica.reyes4242';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241218-00250000'
   OR u.username = 'jessica.reyes4242';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241218-00250000'
   OR u.username = 'jessica.reyes4242';

-- Observe:
--   * Hash Join of the FULL tables + Join Filter: the OR mixes columns of both tables,
--   * so neither condition can be pushed down to a single table's index

-- Observe in every plan:
--   * Scan / join type of every node (Seq Scan, Index Scan, Bitmap Heap Scan, Hash Join ...)
--   * cost=startup..total  (planner units, NOT milliseconds)
--   * rows= estimated  vs  actual rows=  (x loops)  -> how wrong is the estimate?
--   * Rows Removed by Filter: rows read and thrown away
--   * Buffers: shared hit (already in shared_buffers) / read (fetched from OS cache or disk)
--   * Planning Time / Execution Time (run 5-10 times, keep the typical value)

-- Record the numbers in 04_compare.sql, then run 02_optimize.sql.
