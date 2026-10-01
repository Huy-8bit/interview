-- =============================================================================
-- Lab 14 · OR conditions: BitmapOr, missing index, OR across a join — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. OR of two indexed columns of the same table
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR username = 'marilyn.johnston4242';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR username = 'marilyn.johnston4242';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR username = 'marilyn.johnston4242';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR username = 'marilyn.johnston4242';

-- Observe:
--   * BitmapOr of two Bitmap Index Scans (ux_users_email_lower, uq_users_username)

-- -----------------------------------------------------------------------------
-- Q2. OR where one side has NO index
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR phone = '+1-377-523-1035';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR phone = '+1-377-523-1035';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR phone = '+1-377-523-1035';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE lower(email) = 'anna.gomez2037@hotmail.com'
   OR phone = '+1-377-523-1035';

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
WHERE o.order_number = 'ORD-241217-00250000'
   OR u.username = 'marilyn.johnston4242';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241217-00250000'
   OR u.username = 'marilyn.johnston4242';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241217-00250000'
   OR u.username = 'marilyn.johnston4242';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT o.id, o.order_number, u.username
FROM orders o
JOIN users u ON u.id = o.user_id
WHERE o.order_number = 'ORD-241217-00250000'
   OR u.username = 'marilyn.johnston4242';

-- Observe:
--   * Hash Join of the FULL tables + Join Filter: the OR mixes columns of both tables,
--   * so neither condition can be pushed down to a single table's index

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
