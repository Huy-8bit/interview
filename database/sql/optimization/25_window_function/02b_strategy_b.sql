-- =============================================================================
-- Lab 25 · Window functions: the sort behind PARTITION BY ... ORDER BY — OPTIMIZE · Strategy B
-- Strategy B: Rewrite with DISTINCT ON (user_id)
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- 'Latest row per group' is exactly what DISTINCT ON does: keep the first row of
-- each user_id in the ORDER BY order. Simpler plan (Unique over a sorted input),
-- no window function.

-- -----------------------------------------------------------------------------
-- Latest order per customer with DISTINCT ON
-- -----------------------------------------------------------------------------

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT DISTINCT ON (o.user_id)
       o.id, o.user_id, o.status, o.total_amount, o.created_at
FROM orders o
WHERE o.user_id BETWEEN 1 AND 200000
ORDER BY o.user_id, o.created_at DESC;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT DISTINCT ON (o.user_id)
       o.id, o.user_id, o.status, o.total_amount, o.created_at
FROM orders o
WHERE o.user_id BETWEEN 1 AND 200000
ORDER BY o.user_id, o.created_at DESC;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT DISTINCT ON (o.user_id)
       o.id, o.user_id, o.status, o.total_amount, o.created_at
FROM orders o
WHERE o.user_id BETWEEN 1 AND 200000
ORDER BY o.user_id, o.created_at DESC;

-- Observe:
--   * Unique over (Incremental) Sort or over an ordered index scan

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
