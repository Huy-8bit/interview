-- =============================================================================
-- Lab 09 · Expression index: lower(username) — AFTER
-- Same query again, with the optimization applied (02_optimize.sql or 02b/02c...).
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Q1. Case-insensitive login by username
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE lower(username) = lower('Anna.Gomez2037');

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE lower(username) = lower('Anna.Gomez2037');

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE lower(username) = lower('Anna.Gomez2037');

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE lower(username) = lower('Anna.Gomez2037');

-- Observe:
--   * Seq Scan although uq_users_username exists: the index stores username,
--   * the query compares lower(username) - a different expression

-- -----------------------------------------------------------------------------
-- Q2. Exact username (matches the plain index)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE username = 'anna.gomez2037';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE username = 'anna.gomez2037';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE username = 'anna.gomez2037';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE username = 'anna.gomez2037';

-- Observe:
--   * Index Scan using uq_users_username

-- -----------------------------------------------------------------------------
-- Q3. Email compared WITHOUT lower()
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE email = 'anna.gomez2037@hotmail.com';

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE email = 'anna.gomez2037@hotmail.com';

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE email = 'anna.gomez2037@hotmail.com';

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE email = 'anna.gomez2037@hotmail.com';

-- Observe:
--   * Seq Scan: the only email index is on lower(email)

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
