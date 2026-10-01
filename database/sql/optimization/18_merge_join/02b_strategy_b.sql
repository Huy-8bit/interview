-- =============================================================================
-- Lab 18 · Merge Join: two inputs already sorted on the join key — OPTIMIZE · Strategy B
-- Strategy B: (experiment) Merge join on an UNINDEXED key needs an explicit Sort
-- Run on: PRIMARY (localhost:5432), database ecommerce. Execute statement by statement
-- (DBeaver: Ctrl+Enter) or the whole file (DBeaver: Alt+X / psql -f).
-- =============================================================================

-- Start from the baseline: run 05_reset.sql first if another strategy is still applied.

-- What / why:
-- reviews.order_id has no index. Forcing a merge join (hash join disabled)
-- makes the planner sort 5M reviews by order_id first: that Sort is the price
-- of a merge join when the input is not already ordered.

-- -----------------------------------------------------------------------------
-- Orders joined with their reviews, hash join disabled
-- -----------------------------------------------------------------------------

-- Session setting for this query (undone by the RESET below):
SET enable_hashjoin = off;

-- 1) The query itself
SELECT count(*), round(avg(r.rating), 3) AS avg_rating
FROM orders o
JOIN reviews r ON r.order_id = o.id;

-- 2) EXPLAIN: plan + ESTIMATES only. The query is NOT executed.
EXPLAIN
SELECT count(*), round(avg(r.rating), 3) AS avg_rating
FROM orders o
JOIN reviews r ON r.order_id = o.id;

-- 3) EXPLAIN ANALYZE: EXECUTES the query, adds actual time / rows / loops.
EXPLAIN ANALYZE
SELECT count(*), round(avg(r.rating), 3) AS avg_rating
FROM orders o
JOIN reviews r ON r.order_id = o.id;

-- 4) Full detail: buffers (I/O), output columns, non-default settings.
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS)
SELECT count(*), round(avg(r.rating), 3) AS avg_rating
FROM orders o
JOIN reviews r ON r.order_id = o.id;

RESET enable_hashjoin;

-- Observe:
--   * Sort node under the Merge Join: Sort Method: external merge  Disk: ...

-- Undo only this strategy:
-- RESET enable_hashjoin;

-- Next: run 05_reset.sql, compare with 01_before.sql, then 05_reset.sql.
