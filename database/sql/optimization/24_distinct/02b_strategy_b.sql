-- =============================================================================
-- Lab 24 · DISTINCT: full scan vs emulated skip scan, count(DISTINCT) — OPTIMIZE · Strategy B
-- Strategy B: Rewrite Q2: count(*) over SELECT DISTINCT
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- Moving the DISTINCT into a subquery lets the planner choose how to remove
-- duplicates (HashAggregate, parallel partial aggregation, or a sorted index)
-- instead of the aggregate's private sort.

-- -----------------------------------------------------------------------------
-- Q2 rewritten
-- -----------------------------------------------------------------------------

-- 1) The query itself
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*)
FROM (SELECT DISTINCT user_id FROM orders WHERE created_at >= '2026-09-01') s;

-- Observe:
--   * HashAggregate / Unique node, possibly parallel

-- Undo only this strategy:
-- -- (nothing to undo: query rewrite only)

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
