-- =============================================================================
-- Lab 09 · Expression index: lower(username) — OPTIMIZE · Strategy B
-- Strategy B: No DDL: rewrite the email query to match the existing lower(email) index
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Often the index already exists and the query is the problem. ux_users_email_lower
-- is ON users (lower(email)); writing the predicate as lower(email) = lower($1)
-- uses it - and is also the semantically correct case-insensitive comparison.

-- -----------------------------------------------------------------------------
-- Email lookup rewritten as lower(email) = lower(...)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT id, username, email
FROM users
WHERE lower(email) = lower('Anna.Gomez2037@hotmail.com');

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT id, username, email
FROM users
WHERE lower(email) = lower('Anna.Gomez2037@hotmail.com');

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT id, username, email
FROM users
WHERE lower(email) = lower('Anna.Gomez2037@hotmail.com');

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT id, username, email
FROM users
WHERE lower(email) = lower('Anna.Gomez2037@hotmail.com');

-- Observe:
--   * Index Scan using ux_users_email_lower

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
