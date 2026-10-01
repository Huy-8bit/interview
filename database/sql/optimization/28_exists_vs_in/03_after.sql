-- =============================================================================
-- Lab 28 · EXISTS vs IN, NOT EXISTS vs NOT IN (and the NULL trap) — AFTER
-- The recommended form for 'rows without a match': NOT EXISTS.
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- NOT EXISTS (recommended)
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM users u
WHERE u.created_at >= '2026-09-25'
  AND NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);

-- Record the numbers in 04_compare.sql, then run 05_reset.sql.
